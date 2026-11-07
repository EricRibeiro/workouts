import Foundation
import Testing

@testable import DuoKit

/// A fake clock that only moves when the code under test sleeps.
private final class FakeClock: @unchecked Sendable {
    var current = Date(timeIntervalSince1970: 1000)
    var sleeps: [TimeInterval] = []

    func now() -> Date { current }
    func sleep(_ seconds: TimeInterval) {
        sleeps.append(seconds)
        current = current.addingTimeInterval(seconds)
    }
}

/// Serves a scripted sequence of captures; the last one repeats forever.
private final class ScriptedCaptures: @unchecked Sendable {
    private var frames: [String]
    private(set) var taken = 0

    init(_ frames: [String]) { self.frames = frames }

    func next() -> Data {
        let frame = frames[min(taken, frames.count - 1)]
        taken += 1
        return Data(frame.utf8)
    }
}

@Suite struct SettleTests {
    @Test func hashesWithSHA256() {
        #expect(
            Settle.hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test func settlesOnTheSecondCaptureWhenTheScreenIsAlreadyStill() throws {
        let clock = FakeClock()
        let captures = ScriptedCaptures(["a"])
        let result = try Settle.run(now: clock.now, sleep: clock.sleep, capture: captures.next)
        #expect(result.captures == 2)
        #expect(captures.taken == 2)
        #expect(clock.sleeps == [0.3])
        #expect(result.digest == Settle.hex(Data("a".utf8)))
        #expect(abs(result.elapsed - 0.3) < 0.0001)
    }

    @Test func keepsCapturingUntilTwoConsecutiveCapturesMatch() throws {
        let clock = FakeClock()
        let captures = ScriptedCaptures(["a", "b", "a", "c", "c"])
        let result = try Settle.run(now: clock.now, sleep: clock.sleep, capture: captures.next)
        // a, b, a, c differ pairwise (a/b/a is not "equal"), c/c matches on the fifth capture.
        #expect(result.captures == 5)
        #expect(clock.sleeps == [0.3, 0.3, 0.3, 0.3])
        #expect(result.digest == Settle.hex(Data("c".utf8)))
    }

    @Test func timesOutWhenTheScreenNeverStops() {
        let clock = FakeClock()
        var counter = 0
        #expect(throws: DuoError.settleTimeout(seconds: 1, captures: 5)) {
            _ = try Settle.run(timeout: 1, now: clock.now, sleep: clock.sleep) {
                counter += 1
                return Data("frame \(counter)".utf8)
            }
        }
        // Captures at t = 0, 0.3, 0.6, 0.9, 1.2; the check after the last one gives up.
        #expect(counter == 5)
    }

    @Test func aCaptureFailureEndsTheLoop() {
        struct Boom: Error {}
        let clock = FakeClock()
        #expect(throws: Boom.self) {
            _ = try Settle.run(now: clock.now, sleep: clock.sleep) { throw Boom() }
        }
        #expect(clock.sleeps.isEmpty)
    }

    @Test func timeoutMessageNamesTheTimeoutAndCaptureCount() {
        let text = DuoError.settleTimeout(seconds: 10, captures: 33).description
        #expect(text.contains("did not settle"))
        #expect(text.contains("10 s"))
        #expect(text.contains("33 captures"))
    }
}

@Suite struct SettledScreenshotTests {
    @Test func leavesTheSettledCaptureAtThePath() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("settle-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: path) }
        let runner = SettleRunner(frames: ["one", "two", "two"], path: path.path)
        let clock = FakeClock()
        let (shot, settle) = try Screenshot.captureSettled(
            path: path.path,
            udid: "U",
            runner: runner,
            now: clock.now,
            sleep: clock.sleep
        )
        #expect(settle.captures == 3)
        #expect(shot.display.name == "LCD")
        #expect(try String(contentsOf: path, encoding: .utf8) == "two")
    }
}

/// Serves the closed-Duo display table for `devicectl` and, for `simctl io … screenshot`, writes the next scripted
/// frame to the requested path.
private final class SettleRunner: ProcessRunning, @unchecked Sendable {
    private var frames: [String]
    private var taken = 0

    init(frames: [String], path: String) { self.frames = frames }

    func run(_ executable: String, arguments: [String]) throws -> ProcessOutput {
        if arguments.first == "devicectl" {
            let url = try #require(
                Bundle.module.url(forResource: "displays-closed", withExtension: "json", subdirectory: "Fixtures")
            )
            return ProcessOutput(status: 0, stdout: try Data(contentsOf: url), stderr: "")
        }
        let frame = frames[min(taken, frames.count - 1)]
        taken += 1
        try Data(frame.utf8).write(to: URL(fileURLWithPath: try #require(arguments.last)))
        return ProcessOutput(status: 0, stdout: Data(), stderr: "")
    }
}
