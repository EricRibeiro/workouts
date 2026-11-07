import Foundation
import Testing

@testable import DuoKit

private final class LogRunner: ProcessRunning, @unchecked Sendable {
    let output: ProcessOutput
    private let lock = NSLock()
    private var recorded: [[String]] = []

    init(output: ProcessOutput) {
        self.output = output
    }

    var calls: [[String]] { lock.withLock { recorded } }

    func run(_ executable: String, arguments: [String]) throws -> ProcessOutput {
        lock.withLock { recorded.append(arguments) }
        return output
    }
}

private let header = """
    Filtering the log data using "subsystem == "com.ericribeiro.Workouts" AND category == "hinge""
    Timestamp               Ty Process[PID:TID]
    """

private let sample = """
    \(header)
    2026-11-07 10:00:01.100 Df Workouts[101:2a] [com.ericribeiro.Workouts:hinge] hinge status=closed angle=0
    2026-11-07 10:00:05.200 Df Workouts[101:2a] [com.ericribeiro.Workouts:hinge] hinge status=partiallyOpen angle=87
    2026-11-07 10:00:09.300 Df Workouts[101:2a] [com.ericribeiro.Workouts:hinge] hinge status=fullyOpen angle=180
    """

@Suite struct AppHingeTests {
    @Test func takesTheLastHingeLine() {
        #expect(AppHinge.parse(logOutput: sample) == AppHinge(status: "fullyOpen", angleDegrees: 180))
    }

    @Test func readsAStatusWithoutAnAngle() {
        let text = "2026-11-07 10:00:09.300 Df Workouts[1:2] [x:hinge] hinge status=unavailable\n"
        #expect(AppHinge.parse(logOutput: text) == AppHinge(status: "unavailable", angleDegrees: nil))
    }

    @Test func headerAndNoiseAloneAreNotAHingeLine() {
        #expect(AppHinge.parse(logOutput: header) == nil)
        #expect(AppHinge.parse(logOutput: "") == nil)
        #expect(AppHinge.parse(logOutput: "hinge status=\n") == nil)
    }

    @Test func textLine() {
        #expect(AppHinge(status: "closed", angleDegrees: 0).text == "status: closed, angle: 0")
        #expect(AppHinge(status: "unavailable", angleDegrees: nil).text == "status: unavailable")
    }

    @Test func readRunsLogShowOnTheSimulator() throws {
        let runner = LogRunner(output: ProcessOutput(status: 0, stdout: Data(sample.utf8), stderr: ""))
        let hinge = try AppHinge.read(udid: "U-1", runner: runner)
        #expect(hinge.status == "fullyOpen")
        let call = try #require(runner.calls.first)
        #expect(Array(call.prefix(7)) == ["simctl", "spawn", "U-1", "log", "show", "--last", "5m"])
        #expect(call.last == "subsystem == \"com.ericribeiro.Workouts\" AND category == \"hinge\"")
    }

    @Test func noLineIsAnExplainedError() {
        let runner = LogRunner(output: ProcessOutput(status: 0, stdout: Data(header.utf8), stderr: ""))
        do {
            _ = try AppHinge.read(udid: "U-1", runner: runner)
            Issue.record("expected an error")
        } catch {
            #expect("\(error)".contains("-logHinge"))
        }
    }

    @Test func failedLogShowIsReported() {
        let runner = LogRunner(output: ProcessOutput(status: 1, stdout: Data(), stderr: "boom"))
        #expect(throws: DuoError.commandFailed(command: "xcrun simctl spawn … log show", status: 1, stderr: "boom")) {
            try AppHinge.read(udid: "U-1", runner: runner)
        }
    }
}
