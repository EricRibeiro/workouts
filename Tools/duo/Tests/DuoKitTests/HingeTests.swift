import Foundation
import Testing

@testable import DuoKit

private final class HingeRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var guestOutput: ProcessOutput

    init(guestOutput: ProcessOutput) {
        self.guestOutput = guestOutput
    }

    var calls: [[String]] { lock.withLock { recorded } }

    func run(_ executable: String, arguments: [String]) throws -> ProcessOutput {
        lock.withLock { recorded.append(arguments) }
        if arguments.first == "devicectl" {
            let url = try #require(
                Bundle.module.url(forResource: "displays-closed", withExtension: "json", subdirectory: "Fixtures")
            )
            return ProcessOutput(status: 0, stdout: try Data(contentsOf: url), stderr: "")
        }
        return guestOutput
    }
}

private func guest(_ json: String, status: Int32 = 0, stderr: String = "") -> ProcessOutput {
    ProcessOutput(status: status, stdout: Data(json.utf8), stderr: stderr)
}

@Suite struct PoseTests {
    @Test(arguments: [
        (0.0, Pose.closed), (1.9, .closed), (2.0, .closed), (2.1, .halfOpen), (90, .halfOpen), (130, .halfOpen),
        (177.9, .halfOpen), (178.0, .open), (180, .open),
    ])
    func classifies(angle: Double, expected: Pose) {
        #expect(Pose.classify(angleDegrees: angle) == expected)
    }
}

@Suite struct HingeReadingTests {
    @Test func parsesTheGuestJSON() throws {
        let data = Data(#"{"version":1,"angleDegrees":93.4,"angleValid":true}"#.utf8)
        let reading = try HingeReading.parse(data)
        #expect(reading == HingeReading(angleDegrees: 93.4, angleValid: true))
        #expect(reading.pose == .halfOpen)
    }

    @Test func ignoresUnknownFields() throws {
        let reading = try HingeReading.parse(Data(#"{"angleDegrees":0,"angleValid":false,"extra":[1]}"#.utf8))
        #expect(reading.pose == .closed)
        #expect(!reading.angleValid)
    }

    @Test func rejectsMissingFieldsAndGarbage() {
        #expect(throws: DuoError.self) { try HingeReading.parse(Data(#"{"angleDegrees":0}"#.utf8)) }
        #expect(throws: DuoError.self) { try HingeReading.parse(Data("hinge".utf8)) }
    }

    @Test func textAndJSONReports() {
        let closed = HingeReport(reading: HingeReading(angleDegrees: 0, angleValid: true), litPanel: "LCD")
        #expect(closed.text == "angleDegrees: 0, angleValid: true, pose: closed, litPanel: LCD")
        #expect(closed.json == #"{"angleDegrees":0,"angleValid":true,"litPanel":"LCD","pose":"closed"}"#)
        let open = HingeReport(reading: HingeReading(angleDegrees: 179.5, angleValid: true), litPanel: nil)
        #expect(open.text == "angleDegrees: 179.5, angleValid: true, pose: open, litPanel: unresolved")
        #expect(open.json.contains(#""litPanel":null"#))
    }
}

@Suite struct HingeCommandTests {
    @Test func spawnArgumentsCarryTheWindow() {
        #expect(
            Simctl.hingeArguments(udid: "U", guestPath: "/g/duo-guest", windowMs: 500)
                == ["simctl", "spawn", "U", "/g/duo-guest", "hinge", "500"]
        )
    }

    @Test func readsTheGuestAndNamesTheLitPanel() throws {
        let runner = HingeRunner(guestOutput: guest(#"{"version":1,"angleDegrees":0,"angleValid":true}"#))
        let report = try Hinge.read(udid: "U", guestPath: "/g/duo-guest", runner: runner)
        #expect(report.text == "angleDegrees: 0, angleValid: true, pose: closed, litPanel: LCD")
        #expect(runner.calls.first == ["simctl", "spawn", "U", "/g/duo-guest", "hinge", "0"])
    }

    @Test func guestFailureCarriesItsMessage() {
        let runner = HingeRunner(
            guestOutput: guest("", status: 4, stderr: "CMAngleManager delivered no hinge sample within 3 seconds\n")
        )
        do {
            _ = try Hinge.read(udid: "U", guestPath: "/g", runner: runner)
            Issue.record("expected a failure")
        } catch {
            #expect("\(error)".contains("exit status 4: CMAngleManager delivered no hinge sample"))
        }
    }
}
