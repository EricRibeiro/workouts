import Foundation
import Testing

@testable import DuoKit

/// Answers every host call from a closure and records the argument lists in order.
private final class ScriptedRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    private let respond: @Sendable ([String]) -> ProcessOutput

    init(_ respond: @escaping @Sendable ([String]) -> ProcessOutput) {
        self.respond = respond
    }

    var calls: [[String]] { lock.withLock { recorded } }
    var screenshotCalls: [Int] {
        calls.enumerated().filter { $0.element.contains("screenshot") }.map(\.offset)
    }

    func run(_ executable: String, arguments: [String]) throws -> ProcessOutput {
        lock.withLock { recorded.append(arguments) }
        return respond(arguments)
    }
}

private func ok(_ json: String) -> ProcessOutput {
    ProcessOutput(status: 0, stdout: Data(json.utf8), stderr: "")
}

private func displaysJSON(lit: String, outerRotation: String = "rot0", innerRotation: String = "rot90") -> String {
    func panel(_ name: String, primary: Bool, rotation: String) -> String {
        let state = name == lit ? "activeOn" : "off"
        return """
            {"name":"\(name)","backlightState":"\(state)","nativeSize":[1398,2034],"pointScale":3,\
            "currentOrientation":"\(rotation)","nativeOrientation":"rot0","primary":\(primary),"type":{"integrated":{}}}
            """
    }
    return """
        {"result":{"displays":[\(panel("LCD", primary: true, rotation: outerRotation)),\
        \(panel("LCD-1", primary: false, rotation: innerRotation))]}}
        """
}

private func hingeJSON(_ angle: Double) -> String {
    #"{"version":1,"angleDegrees":\#(angle),"angleValid":true}"#
}

/// A clock that only moves when the code under test sleeps.
private final class FakeClock: @unchecked Sendable {
    var elapsed: TimeInterval = 0
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    func now() -> Date { start.addingTimeInterval(elapsed) }
    func sleep(_ seconds: TimeInterval) { elapsed += seconds }
}

@Suite struct FoldRunTests {
    private func runner(angle: Double, lit: String) -> ScriptedRunner {
        ScriptedRunner { arguments in
            if arguments.first == "devicectl" { return ok(displaysJSON(lit: lit)) }
            if arguments.contains("hinge") { return ok(hingeJSON(angle)) }
            return ProcessOutput(status: 0, stdout: Data(), stderr: "")
        }
    }

    @Test func takesThePNGOnlyAfterTheHingeAndPanelAreVerified() throws {
        let scripted = runner(angle: 180, lit: "LCD-1")
        let clock = FakeClock()
        let result = try Fold.run(
            target: try #require(FoldTarget.parse("open")),
            udid: "U",
            guestPath: "/g",
            png: "/tmp/o.png",
            runner: scripted,
            now: clock.now,
            sleep: clock.sleep
        )
        #expect(result.summary.hasPrefix("fold open: hinge 180 deg (open), lit panel LCD-1\n/tmp/o.png"))
        let calls = scripted.calls
        #expect(calls.first == ["simctl", "spawn", "U", "/g", "set", "open"])
        #expect(scripted.screenshotCalls == [calls.count - 1])
        #expect(calls.last == ["simctl", "io", "U", "screenshot", "--display=LCD-1", "/tmp/o.png"])
        #expect(calls.contains { $0.contains("hinge") })
    }

    @Test func aHingeThatNeverArrivesFailsWithTheObservedAngleAndNoPNG() throws {
        let scripted = runner(angle: 0, lit: "LCD")
        let clock = FakeClock()
        do {
            _ = try Fold.run(
                target: try #require(FoldTarget.parse("open")),
                udid: "U",
                guestPath: "/g",
                png: "/tmp/o.png",
                runner: scripted,
                now: clock.now,
                sleep: clock.sleep
            )
            Issue.record("expected a failure")
        } catch {
            let message = "\(error)"
            #expect(message.contains("fold open not reached: hinge 0.0 deg after 8 reads"))
            #expect(message.contains("lit panel LCD"))
        }
        #expect(scripted.screenshotCalls.isEmpty)
    }

    @Test func aWrongLitPanelFailsAfterTheDeadlineWithNoPNG() throws {
        let scripted = runner(angle: 180, lit: "LCD")
        let clock = FakeClock()
        do {
            _ = try Fold.run(
                target: try #require(FoldTarget.parse("open")),
                udid: "U",
                guestPath: "/g",
                png: "/tmp/o.png",
                runner: scripted,
                now: clock.now,
                sleep: clock.sleep
            )
            Issue.record("expected a failure")
        } catch {
            #expect("\(error)".contains("hinge 180.0 deg (open) but lit panel LCD, expected LCD-1"))
        }
        #expect(clock.elapsed == PanelCheck.timeout)
        #expect(scripted.screenshotCalls.isEmpty)
    }
}

@Suite struct OrientRunTests {
    private func runner(device: String, outerRotation: String) -> ScriptedRunner {
        ScriptedRunner { arguments in
            if arguments.starts(with: ["devicectl", "device", "orientation"]) {
                return ok(#"{"result":{"deviceOrientation":"\#(device)"}}"#)
            }
            if arguments.first == "devicectl" { return ok(displaysJSON(lit: "LCD", outerRotation: outerRotation)) }
            return ProcessOutput(status: 0, stdout: Data(), stderr: "")
        }
    }

    @Test func takesThePNGOnlyAfterTheOrientationIsVerified() throws {
        let scripted = runner(device: "landscapeLeft", outerRotation: "rot270")
        let result = try Orient.run(
            target: .landscapeLeft,
            udid: "U",
            guestPath: "/g",
            png: "/tmp/ll.png",
            runner: scripted,
            sleep: { _ in }
        )
        #expect(result.summary.hasPrefix("orient landscape-left: device landscapeLeft, lit panel LCD rot270\n"))
        let calls = scripted.calls
        #expect(calls.first == ["simctl", "spawn", "U", "/g", "rotate", "landscape-left"])
        #expect(scripted.screenshotCalls == [calls.count - 1])
    }

    @Test func aStuckDeviceFailsWithWhatWasSeenAndNoPNG() throws {
        let scripted = runner(device: "landscapeLeft", outerRotation: "rot0")
        var sleeps = 0
        do {
            _ = try Orient.run(
                target: .portrait,
                udid: "U",
                guestPath: "/g",
                png: "/tmp/p.png",
                runner: scripted,
                sleep: { _ in sleeps += 1 }
            )
            Issue.record("expected a failure")
        } catch {
            #expect(
                "\(error)".contains(
                    "orient portrait not reached after 24 polls: device landscapeLeft, lit panel LCD rot0"
                )
            )
        }
        #expect(sleeps == 23)
        #expect(scripted.screenshotCalls.isEmpty)
    }
}

@Suite struct ScreenshotRetryTests {
    private func runner(darkPolls: Int) -> ScriptedRunner {
        let polls = LockedCounter()
        return ScriptedRunner { arguments in
            if arguments.first == "devicectl" {
                return ok(displaysJSON(lit: polls.next() <= darkPolls ? "none" : "LCD"))
            }
            return ProcessOutput(status: 0, stdout: Data(), stderr: "")
        }
    }

    @Test func aBriefBlackoutIsRetried() throws {
        var sleeps: [TimeInterval] = []
        let result = try Screenshot.capture(
            path: "/tmp/a.png",
            udid: "U",
            runner: runner(darkPolls: 2),
            sleep: { sleeps.append($0) }
        )
        #expect(result.display.name == "LCD")
        #expect(sleeps == [0.5, 0.5])
    }

    @Test func givesUpAfterThreeRetries() {
        var sleeps = 0
        #expect(throws: DuoError.litPanelCount(0, names: [])) {
            try Screenshot.capture(
                path: "/tmp/a.png",
                udid: "U",
                runner: runner(darkPolls: 99),
                sleep: { _ in sleeps += 1 }
            )
        }
        #expect(sleeps == 3)
    }

    @Test func explicitPanelsAreNotRetried() throws {
        var sleeps = 0
        let result = try Screenshot.capture(
            path: "/tmp/a.png",
            udid: "U",
            selector: .inner,
            runner: runner(darkPolls: 99),
            sleep: { _ in sleeps += 1 }
        )
        #expect(result.display.name == "LCD-1")
        #expect(sleeps == 0)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1; return value
        }
    }
}

@Suite struct ProcessTimeoutTests {
    @Test func aQuickProcessReturnsItsOutput() throws {
        let output = try SystemProcessRunner().run("/bin/echo", arguments: ["hi"])
        #expect(output.status == 0)
        #expect(String(decoding: output.stdout, as: UTF8.self) == "hi\n")
    }

    @Test func aHangingProcessIsTerminated() {
        let started = Date()
        #expect(throws: DuoError.timedOut(command: "sleep 30", seconds: 0.5)) {
            try SystemProcessRunner(timeout: 0.5).run("/bin/sleep", arguments: ["30"])
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func aProcessThatIgnoresSIGTERMIsKilled() {
        let started = Date()
        #expect(throws: DuoError.self) {
            try SystemProcessRunner(timeout: 0.5, killGrace: 0.5)
                .run("/bin/sh", arguments: ["-c", "trap '' TERM; exec sleep 30"])
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func theMessageNamesTheCommandAndTheLimit() {
        #expect(
            DuoError.timedOut(command: "xcrun simctl io U screenshot", seconds: 60).description
                == "xcrun simctl io U screenshot timed out after 60 s"
        )
    }
}

@Suite struct PoseRunTests {
    @Test func foldsThenRotatesAndTakesTheOnlyPNGLast() throws {
        let scripted = ScriptedRunner { arguments in
            if arguments.starts(with: ["devicectl", "device", "orientation"]) {
                return ok(#"{"result":{"deviceOrientation":"landscapeLeft"}}"#)
            }
            if arguments.first == "devicectl" { return ok(displaysJSON(lit: "LCD-1", innerRotation: "rot0")) }
            if arguments.contains("hinge") { return ok(hingeJSON(180)) }
            return ProcessOutput(status: 0, stdout: Data(), stderr: "")
        }
        let clock = FakeClock()
        let result = try PoseCommand.run(
            pose: .openTall,
            udid: "U",
            guestPath: "/g",
            png: "/tmp/t.png",
            runner: scripted,
            now: clock.now,
            sleep: clock.sleep
        )
        #expect(
            result.summary.hasPrefix(
                "pose open-tall: hinge 180 deg (open), lit panel LCD-1, device landscapeLeft, lit panel LCD-1 rot0\n/tmp/t.png"
            )
        )
        let calls = scripted.calls
        let set = try #require(calls.firstIndex(of: ["simctl", "spawn", "U", "/g", "set", "open"]))
        let rotate = try #require(calls.firstIndex(of: ["simctl", "spawn", "U", "/g", "rotate", "landscape-left"]))
        #expect(set < rotate)
        #expect(scripted.screenshotCalls == [calls.count - 1])
    }

    @Test func aFailedFoldNeverRotates() throws {
        let scripted = ScriptedRunner { arguments in
            if arguments.first == "devicectl" { return ok(displaysJSON(lit: "LCD")) }
            if arguments.contains("hinge") { return ok(hingeJSON(0)) }
            return ProcessOutput(status: 0, stdout: Data(), stderr: "")
        }
        let clock = FakeClock()
        #expect(throws: DuoError.self) {
            try PoseCommand.run(
                pose: .openWide,
                udid: "U",
                guestPath: "/g",
                png: "/tmp/w.png",
                runner: scripted,
                now: clock.now,
                sleep: clock.sleep
            )
        }
        #expect(!scripted.calls.contains { $0.contains("rotate") })
        #expect(scripted.screenshotCalls.isEmpty)
    }
}
