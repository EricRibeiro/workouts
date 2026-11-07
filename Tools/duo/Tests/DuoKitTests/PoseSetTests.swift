import Foundation
import Testing

@testable import DuoKit

/// A simulator in a box: `set` moves the hinge, `rotate` turns the device, the reads report both, and a screenshot
/// writes a file. `failing` makes matching host calls exit non-zero.
private final class FakeDuo: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    private var angle = 0.0
    private var orientation = "portrait"
    private var shotCount = 0
    private let failing: @Sendable ([String]) -> Bool

    init(failing: @escaping @Sendable ([String]) -> Bool = { _ in false }) {
        self.failing = failing
    }

    var calls: [[String]] { lock.withLock { recorded } }

    /// The `set`/`rotate` calls, as `closed`, `portrait`, `open`, `landscape-left`, ...
    var moves: [String] {
        calls.compactMap { $0.count > 5 && ($0[4] == "set" || $0[4] == "rotate") ? $0[5] : nil }
    }

    func run(_ executable: String, arguments: [String]) throws -> ProcessOutput {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(arguments)
        if failing(arguments) { return ProcessOutput(status: 1, stdout: Data(), stderr: "boom") }
        if arguments.count > 5, arguments[4] == "set" {
            angle = arguments[5] == "open" ? 180 : 0
        } else if arguments.count > 5, arguments[4] == "rotate" {
            orientation = arguments[5]
        } else if arguments.contains("hinge") {
            return ok(#"{"version":1,"angleDegrees":\#(angle),"angleValid":true}"#)
        } else if arguments.starts(with: ["devicectl", "device", "orientation"]) {
            let name = orientation == "landscape-left" ? "landscapeLeft" : orientation
            return ok(#"{"result":{"deviceOrientation":"\#(name)"}}"#)
        } else if arguments.first == "devicectl" {
            return ok(displays())
        } else if arguments.contains("screenshot"), let path = arguments.last {
            shotCount += 1
            try Data("frame".utf8).write(to: URL(fileURLWithPath: path))
        }
        return ProcessOutput(status: 0, stdout: Data(), stderr: "")
    }

    private func ok(_ json: String) -> ProcessOutput {
        ProcessOutput(status: 0, stdout: Data(json.utf8), stderr: "")
    }

    private func displays() -> String {
        let turn = orientation == "landscape-left" ? 270 : 0
        func panel(_ name: String, primary: Bool, portrait: Int) -> String {
            let state = (name == "LCD") == (angle == 0) ? "activeOn" : "off"
            return """
                {"name":"\(name)","backlightState":"\(state)","nativeSize":[1398,2034],"pointScale":3,\
                "currentOrientation":"rot\((portrait + turn) % 360)","nativeOrientation":"rot0",\
                "primary":\(primary),"type":{"integrated":{}}}
                """
        }
        return """
            {"result":{"displays":[\(panel("LCD", primary: true, portrait: 0)),\
            \(panel("LCD-1", primary: false, portrait: 90))]}}
            """
    }
}

private final class FakeClock: @unchecked Sendable {
    var elapsed: TimeInterval = 0
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    func now() -> Date { start.addingTimeInterval(elapsed) }
    func sleep(_ seconds: TimeInterval) { elapsed += seconds }
}

private func scratchDirectory() -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent("duo-poses-\(UUID().uuidString)").path
}

@Suite struct PoseSetTests {
    @Test func runsTheFourPosesInOrderAndRestoresClosedPortrait() throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let fake = FakeDuo()
        let clock = FakeClock()
        let report = PoseSet.run(
            directory: directory,
            udid: "U",
            guestPath: "/g",
            runner: fake,
            now: clock.now,
            sleep: clock.sleep
        )
        #expect(report.succeeded)
        #expect(report.failureMessage == nil)
        // Each pose is a fold then a rotation; the fifth pair is the restore.
        #expect(
            fake.moves == [
                "closed", "portrait", "closed", "landscape-left", "open", "portrait", "open", "landscape-left",
                "closed", "portrait",
            ]
        )
        #expect(report.lines.count == 4)
        let names = ["closed-portrait", "closed-landscape", "open-wide", "open-tall"]
        for (line, name) in zip(report.lines, names) {
            #expect(line.hasPrefix("\(name): \(directory)/\(name).png "))
        }
        for name in names {
            #expect(FileManager.default.fileExists(atPath: "\(directory)/\(name).png"))
        }
        // The restore is not photographed: four poses, each settled by two captures.
        #expect(fake.calls.filter { $0.contains("screenshot") }.count == 8)
        #expect(fake.calls.last?.contains("screenshot") == false)
    }

    @Test func restoresClosedPortraitAndReportsWhenAPoseFailsMidSet() throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        // The hinge refuses to open: the third pose (open-wide) fails.
        let fake = FakeDuo(failing: { $0.contains("set") && $0.contains("open") })
        let clock = FakeClock()
        let report = PoseSet.run(
            directory: directory,
            udid: "U",
            guestPath: "/g",
            runner: fake,
            now: clock.now,
            sleep: clock.sleep
        )
        #expect(!report.succeeded)
        #expect(report.failure != nil)
        #expect(report.restoreFailure == nil)
        #expect(report.failureMessage?.contains("boom") == true)
        #expect(report.lines.count == 2)
        #expect(fake.moves == ["closed", "portrait", "closed", "landscape-left", "open", "closed", "portrait"])
        #expect(!FileManager.default.fileExists(atPath: "\(directory)/open-wide.png"))
        #expect(!FileManager.default.fileExists(atPath: "\(directory)/open-tall.png"))
    }

    @Test func aFailedRestoreIsReportedBesideTheOriginalFailure() throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        // Every rotation fails: the first pose fails, and so does the restore's own rotation.
        let fake = FakeDuo(failing: {
            $0.contains("rotate") && ($0.contains("landscape-left") || $0.contains("portrait"))
        })
        let clock = FakeClock()
        let report = PoseSet.run(
            directory: directory,
            udid: "U",
            guestPath: "/g",
            runner: fake,
            now: clock.now,
            sleep: clock.sleep
        )
        #expect(!report.succeeded)
        #expect(report.failure != nil)
        #expect(report.restoreFailure != nil)
        #expect(report.failureMessage?.contains("restoring closed-portrait also failed") == true)
        #expect(report.lines.isEmpty)
        // The restore was still attempted, last.
        #expect(Array(fake.moves.suffix(2)) == ["closed", "portrait"])
    }

    @Test func namesTheFilesAfterThePoses() {
        #expect(PoseSet.path(in: "/tmp/p", for: .openTall) == "/tmp/p/open-tall.png")
        #expect(PoseSet.order.map(\.rawValue) == ["closed-portrait", "closed-landscape", "open-wide", "open-tall"])
    }
}
