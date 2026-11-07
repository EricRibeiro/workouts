import Foundation
import Testing

@testable import DuoKit

private func plan(_ json: String) throws -> KeyframePlan { try KeyframePlan.parse(json) }

private let unfold = #"[{"atMs":0,"angle":0},{"atMs":3000,"angle":180}]"#

@Suite struct KeyframePlanParsingTests {
    @Test func parsesTheDocumentedForm() throws {
        let parsed = try plan(unfold)
        #expect(parsed.keyframes == [Keyframe(atMs: 0, angle: 0), Keyframe(atMs: 3000, angle: 180)])
        #expect(parsed.durationMs == 3000)
        #expect(parsed.finalAngle == 180)
    }

    @Test func acceptsFractionalValues() throws {
        #expect(try plan(#"[{"atMs":0,"angle":12.5},{"atMs":250.5,"angle":0.5}]"#).durationMs == 250.5)
    }

    @Test(
        arguments: [
            "",
            "not json",
            "{}",
            "[]",
            #"[{"atMs":0,"angle":0}]"#,
            #"[{"atMs":0}]"#,
            #"[{"atMs":"0","angle":0},{"atMs":10,"angle":1}]"#,
            #"[{"atMs":10,"angle":0},{"atMs":20,"angle":90}]"#,
            #"[{"atMs":0,"angle":0},{"atMs":0,"angle":90}]"#,
            #"[{"atMs":0,"angle":0},{"atMs":500,"angle":90},{"atMs":400,"angle":10}]"#,
            #"[{"atMs":0,"angle":-1},{"atMs":100,"angle":90}]"#,
            #"[{"atMs":0,"angle":0},{"atMs":100,"angle":181}]"#,
            #"[{"atMs":0,"angle":0},{"atMs":60001,"angle":90}]"#,
        ]
    )
    func rejectsInvalidInput(json: String) {
        #expect(throws: DuoError.self) { try KeyframePlan.parse(json) }
    }

    @Test func theErrorNamesTheRuleThatWasBroken() {
        func message(_ json: String) -> String {
            do {
                _ = try KeyframePlan.parse(json)
                return ""
            } catch { return "\(error)" }
        }
        #expect(message(#"[{"atMs":5,"angle":0},{"atMs":9,"angle":1}]"#).contains("first atMs must be 0"))
        #expect(message(#"[{"atMs":0,"angle":0},{"atMs":9,"angle":1},{"atMs":9,"angle":2}]"#).contains("ascending"))
        #expect(message(#"[{"atMs":0,"angle":0},{"atMs":9,"angle":200}]"#).contains("0...180"))
        #expect(message("[]").contains("2 to 64 keyframes"))
        #expect(message("x").contains("JSON array"))
    }

    @Test func atMostSixtyFourKeyframes() throws {
        func make(_ count: Int) -> String {
            let entries = (0..<count).map { #"{"atMs":\#($0 * 10),"angle":\#($0 % 181)}"# }
            return "[" + entries.joined(separator: ",") + "]"
        }
        #expect(try plan(make(64)).keyframes.count == 64)
        #expect(throws: DuoError.self) { try plan(make(65)) }
    }
}

@Suite struct KeyframeInterpolationTests {
    @Test func interpolatesLinearlyBetweenNeighbours() throws {
        let parsed = try plan(#"[{"atMs":0,"angle":0},{"atMs":1000,"angle":100},{"atMs":2000,"angle":50}]"#)
        #expect(parsed.angle(atMs: 0) == 0)
        #expect(parsed.angle(atMs: 250) == 25)
        #expect(parsed.angle(atMs: 1000) == 100)
        #expect(parsed.angle(atMs: 1500) == 75)
        #expect(parsed.angle(atMs: 2000) == 50)
    }

    @Test func clampsOutsideTheMotion() throws {
        let parsed = try plan(unfold)
        #expect(parsed.angle(atMs: -5) == 0)
        #expect(parsed.angle(atMs: 9_999) == 180)
    }
}

@Suite struct KeyframeScheduleTests {
    @Test func threeSecondsAtSixtyHertzIsOneHundredEightyOneFrames() throws {
        let frames = try plan(unfold).frames
        #expect(frames.count == 181)
        #expect(frames.first == HingeFrame(offset: 0, angle: 0))
        #expect(frames.last == HingeFrame(offset: 3, angle: 180))
    }

    @Test func offsetsAreMultiplesOfOneSixtiethComputedFromTheIndex() throws {
        let frames = try plan(unfold).frames
        for (index, frame) in frames.enumerated() { #expect(frame.offset == Double(index) / 60) }
    }

    @Test func aDurationBetweenTicksGetsAnExactFinalFrame() throws {
        let frames = try plan(#"[{"atMs":0,"angle":0},{"atMs":100,"angle":60}]"#).frames
        // 100 ms: ticks at 0, 1/60 (16.7 ms) ... 5/60 (83.3 ms), then the exact end at 100 ms.
        #expect(frames.count == 7)
        #expect(frames[5].offset == 5.0 / 60)
        #expect(frames.last == HingeFrame(offset: 0.1, angle: 60))
    }

    @Test func anglesNeverLeaveTheKeyframeRangeAndRiseMonotonically() throws {
        let angles = try plan(unfold).frames.map(\.angle)
        #expect(angles.allSatisfy { (0...180).contains($0) })
        #expect(zip(angles, angles.dropFirst()).allSatisfy { $0 <= $1 })
    }
}

/// Advances only when slept on; `onSleep` lets a test record the order of events.
private final class FakeFrameClock: FrameClock {
    var time = 100.0
    var sleptUntil: [Double] = []
    var events: [String] = []
    /// Seconds added to `now()` after each `send`, to model a slow dispatch.
    var stall = 0.0

    func now() -> TimeInterval { time }

    func sleep(until deadline: TimeInterval) {
        sleptUntil.append(deadline)
        if deadline > time { time = deadline }
    }
}

private final class FakeSender: HingeSending {
    let clock: FakeFrameClock
    var sent: [(at: Double, angle: Double)] = []
    var failAfter: Int?

    init(clock: FakeFrameClock) { self.clock = clock }

    func send(angle: Double) throws {
        if let failAfter, sent.count >= failAfter {
            throw DuoError.commandFailed(command: "stream", status: 1, stderr: "gone")
        }
        sent.append((clock.time, angle))
        clock.events.append("frame")
        clock.time += clock.stall
    }
}

private final class FakeRecorder: VideoRecording {
    let clock: FakeFrameClock
    var startedAt: Double?
    var stoppedAt: Double?

    init(clock: FakeFrameClock) { self.clock = clock }

    func start() throws {
        startedAt = clock.time
        clock.events.append("start")
    }

    func stop() throws {
        stoppedAt = clock.time
        clock.events.append("stop")
    }
}

@Suite struct KeyframePlaybackTests {
    @Test func everyFrameGoesOutAtItsAbsoluteDeadline() throws {
        let clock = FakeFrameClock()
        let sender = FakeSender(clock: clock)
        let playback = try Keyframes.play(plan: try plan(unfold), sender: sender, clock: clock)
        #expect(playback.frames == 181)
        #expect(playback.maxLatenessMs == 0)
        #expect(sender.sent.count == 181)
        for (index, sent) in sender.sent.enumerated() {
            #expect(sent.at == 100 + Double(index) / 60)
        }
        #expect(sender.sent.last?.angle == 180)
    }

    @Test func aSlowSendMakesLaterFramesLateButNeverShiftsTheirDeadlines() throws {
        let clock = FakeFrameClock()
        clock.stall = 0.005  // 5 ms per send, less than one 16.7 ms frame: no drift may accumulate
        let sender = FakeSender(clock: clock)
        let playback = try Keyframes.play(plan: try plan(unfold), sender: sender, clock: clock)
        #expect(playback.maxLatenessMs == 0)
        #expect(clock.sleptUntil.enumerated().allSatisfy { $0.element == 100 + Double($0.offset) / 60 })
        #expect(sender.sent.last?.at == 103)
    }

    @Test func aStallLongerThanAFrameIsReportedAsLatenessAndTheScheduleCatchesUp() throws {
        let clock = FakeFrameClock()
        let late = FakeSender(clock: clock)
        let hiccup = HiccupSender(inner: late, clock: clock, afterFrame: 0, seconds: 0.05)
        let playback = try Keyframes.play(plan: try plan(unfold), sender: hiccup, clock: clock)
        #expect(playback.maxLatenessMs > 30 && playback.maxLatenessMs < 40)  // 50 ms - 16.7 ms
        #expect(late.sent.last?.at == 103)  // later frames kept their original deadlines
    }

    @Test func theRecorderBracketsTheMotionWithATail() throws {
        let clock = FakeFrameClock()
        let sender = FakeSender(clock: clock)
        let recorder = FakeRecorder(clock: clock)
        _ = try Keyframes.play(plan: try plan(unfold), sender: sender, recorder: recorder, clock: clock)
        #expect(clock.events.first == "start")
        #expect(clock.events.last == "stop")
        #expect(clock.events.filter { $0 == "frame" }.count == 181)
        #expect(recorder.startedAt == 100)
        let stopped = try #require(recorder.stoppedAt)
        #expect(abs(stopped - (103 + Keyframes.recordingTail)) < 1e-9)
    }

    @Test func aFailingSendStillStopsTheRecorderAndRethrows() throws {
        let clock = FakeFrameClock()
        let sender = FakeSender(clock: clock)
        sender.failAfter = 10
        let recorder = FakeRecorder(clock: clock)
        #expect(throws: DuoError.self) {
            try Keyframes.play(plan: try plan(unfold), sender: sender, recorder: recorder, clock: clock)
        }
        #expect(recorder.stoppedAt != nil)
        #expect(sender.sent.count == 10)
    }

    @Test func withoutARecorderThereIsNoTail() throws {
        let clock = FakeFrameClock()
        let sender = FakeSender(clock: clock)
        _ = try Keyframes.play(plan: try plan(unfold), sender: sender, clock: clock)
        #expect(clock.time == 103)
    }
}

/// Adds `seconds` to the clock once, after the given frame has been sent.
private final class HiccupSender: HingeSending {
    let inner: FakeSender
    let clock: FakeFrameClock
    let afterFrame: Int
    let seconds: Double

    init(inner: FakeSender, clock: FakeFrameClock, afterFrame: Int, seconds: Double) {
        self.inner = inner
        self.clock = clock
        self.afterFrame = afterFrame
        self.seconds = seconds
    }

    func send(angle: Double) throws {
        try inner.send(angle: angle)
        if inner.sent.count == afterFrame + 1 { clock.time += seconds }
    }
}

@Suite struct KeyframeArgumentTests {
    @Test func guestStreamAndRecorderCommandLines() {
        #expect(GuestHingeStream.arguments(udid: "U", guestPath: "/g") == ["simctl", "spawn", "U", "/g", "stream"])
        #expect(
            SimctlRecorder.arguments(udid: "U", displayName: "LCD", path: "/tmp/a.mov")
                == ["simctl", "io", "U", "recordVideo", "--display=LCD", "--force", "/tmp/a.mov"]
        )
    }

    @Test func theFinalAngleDecidesThePoseToVerify() throws {
        #expect(try #require(FoldTarget.parse(String(plan(unfold).finalAngle))).pose == .open)
        let closing = try plan(#"[{"atMs":0,"angle":180},{"atMs":500,"angle":0}]"#)
        #expect(try #require(FoldTarget.parse(String(closing.finalAngle))).pose == .closed)
        let middle = try plan(#"[{"atMs":0,"angle":0},{"atMs":500,"angle":130}]"#)
        #expect(try #require(FoldTarget.parse(String(middle.finalAngle))).pose == .halfOpen)
    }
}

/// The two long-lived children, driven through `/bin/sh -c` stand-ins instead of xcrun. Nothing here waits on a fixed
/// delay: every stand-in either exits at once or ends on the SIGINT/EOF the code under test sends.
@Suite struct KeyframeChildProcessTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("duo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func leftovers(_ directory: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    private func errFiles(_ directory: URL) -> [String] {
        leftovers(directory).filter { $0.hasSuffix(".err") }
    }

    private func recorder(script: String, movie: String, scratch: URL) -> SimctlRecorder {
        SimctlRecorder(
            udid: "U",
            path: movie,
            displayName: "LCD",
            executable: "/bin/sh",
            arguments: ["-c", script, "sh", movie],
            scratch: scratch
        )
    }

    private func guest(script: String, scratch: URL, readyTimeout: TimeInterval = 10) throws -> GuestHingeStream {
        try GuestHingeStream(
            udid: "U",
            guestPath: "/g",
            readyTimeout: readyTimeout,
            executable: "/bin/sh",
            arguments: ["-c", script],
            scratch: scratch
        )
    }

    private func waitUntilExited(_ recorder: SimctlRecorder) {
        let deadline = Date().addingTimeInterval(1.5)
        while recorder.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.002) }
    }

    // MARK: recorder

    @Test(.timeLimit(.minutes(1))) func aRecorderThatDiedEarlyFailsTheStopWithItsStatusAndStderr() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let movie = dir.appendingPathComponent("a.mov").path
        let rec = recorder(script: #"echo "Recording started" >&2; echo boom >&2; exit 3"#, movie: movie, scratch: dir)
        let began = Date()
        try rec.start()
        waitUntilExited(rec)
        #expect(!rec.isRunning)
        do {
            try rec.stop(timeout: 1)
            Issue.record("stop must not succeed after the recorder died")
        } catch DuoError.commandFailed(_, let status, let stderr) {
            #expect(status == 3)
            #expect(stderr.contains("boom"))
        }
        #expect(Date().timeIntervalSince(began) < 2)
        #expect(errFiles(dir).isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func aRecorderThatWroteNothingFailsTheStop() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let movie = dir.appendingPathComponent("b.mov").path
        // Exits 0 on SIGINT but never wrote a movie.
        let script = #"trap 'exit 0' INT; echo "Recording started" >&2; sleep 30 & wait"#
        let rec = recorder(script: script, movie: movie, scratch: dir)
        let began = Date()
        try rec.start()
        do {
            try rec.stop(timeout: 1.5)
            Issue.record("an empty recording must not count as success")
        } catch DuoError.commandFailed(_, _, let stderr) {
            #expect(stderr.contains("missing or empty"))
        }
        #expect(Date().timeIntervalSince(began) < 2)
        #expect(errFiles(dir).isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func aRecorderThatFinalisedAMovieStops() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let movie = dir.appendingPathComponent("c.mov").path
        let script = #"trap 'echo frames > "$1"; exit 0' INT; echo "Recording started" >&2; sleep 30 & wait"#
        let rec = recorder(script: script, movie: movie, scratch: dir)
        let began = Date()
        try rec.start()
        try rec.stop(timeout: 1.5)
        #expect(Date().timeIntervalSince(began) < 2)
        #expect(errFiles(dir).isEmpty)
    }

    // MARK: guest stream

    @Test(.timeLimit(.minutes(1))) func aGuestThatExitsAtOnceThrowsItsStderrWithoutWaitingForTheReadyTimeout() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let began = Date()
        do {
            _ = try guest(script: "echo 'no IOKit symbols' >&2; exit 7", scratch: dir, readyTimeout: 10)
            Issue.record("a guest that exits before the ready line must fail init")
        } catch DuoError.commandFailed(_, let status, let stderr) {
            #expect(status == 7)
            #expect(stderr.contains("no IOKit symbols"))
        }
        #expect(Date().timeIntervalSince(began) < 2)
        #expect(leftovers(dir).isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func aGuestThatNeverSaysReadyTimesOutAndCleansUp() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let began = Date()
        do {
            _ = try guest(script: "sleep 30", scratch: dir, readyTimeout: 0.3)
            Issue.record("expected a ready timeout")
        } catch DuoError.timedOut(_, let seconds) {
            #expect(seconds == 0.3)
        }
        #expect(Date().timeIntervalSince(began) < 2)
        #expect(leftovers(dir).isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func aReadyGuestTakesAnglesAndFinishesCleanly() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let began = Date()
        let stream = try guest(script: #"echo '{"ready":true}'; cat > /dev/null"#, scratch: dir)
        try stream.send(angle: 90)
        try stream.finish()
        #expect(Date().timeIntervalSince(began) < 2)
        #expect(leftovers(dir).isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func aGuestThatFailsAfterReadyReportsItAtFinish() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stream = try guest(script: #"echo '{"ready":true}'; cat > /dev/null; echo late >&2; exit 4"#, scratch: dir)
        do {
            try stream.finish()
            Issue.record("a non-zero exit must fail finish")
        } catch DuoError.commandFailed(_, let status, let stderr) {
            #expect(status == 4)
            #expect(stderr.contains("late"))
        }
        #expect(leftovers(dir).isEmpty)
    }
}
