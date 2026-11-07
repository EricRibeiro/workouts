import Darwin
import Foundation

/// One `--keyframes` entry: the hinge is at `angle` degrees `atMs` milliseconds after the motion starts.
public struct Keyframe: Sendable, Equatable, Decodable {
    public var atMs: Double
    public var angle: Double

    public init(atMs: Double, angle: Double) {
        self.atMs = atMs
        self.angle = angle
    }
}

/// One hinge event of the 60 Hz schedule: `offset` seconds after the start, at `angle` degrees.
public struct HingeFrame: Sendable, Equatable {
    public var offset: TimeInterval
    public var angle: Double
}

/// A validated keyframe list and the 60 Hz frames it expands to. Port of `Fold.m` `readFrames`/`runFrames`:
/// 2...64 keyframes, at most 60 s, linear interpolation between neighbours.
public struct KeyframePlan: Sendable, Equatable {
    public static let frameRate = 60.0
    public static let keyframeCount = 2...64
    public static let maxDurationMs = 60_000.0

    public var keyframes: [Keyframe]

    public var durationMs: Double { keyframes.last?.atMs ?? 0 }
    public var finalAngle: Double { keyframes.last?.angle ?? 0 }

    /// Parses `[{"atMs":0,"angle":0},{"atMs":3000,"angle":180}]`. Throws `DuoError.verificationFailed` naming the
    /// rule that was broken: a JSON array of objects, `atMs` strictly ascending from 0 to at most 60000, `angle` in 0...180.
    public static func parse(_ json: String) throws -> KeyframePlan {
        let form = "--keyframes must be a JSON array like [{\"atMs\":0,\"angle\":0},{\"atMs\":3000,\"angle\":180}]"
        let keyframes: [Keyframe]
        do {
            keyframes = try JSONDecoder().decode([Keyframe].self, from: Data(json.utf8))
        } catch {
            throw DuoError.verificationFailed(form)
        }
        return try KeyframePlan(validating: keyframes)
    }

    public init(validating keyframes: [Keyframe]) throws {
        func fail(_ message: String) -> DuoError { .verificationFailed("--keyframes: " + message) }
        guard Self.keyframeCount.contains(keyframes.count) else {
            let range = Self.keyframeCount
            throw fail("needs \(range.lowerBound) to \(range.upperBound) keyframes (got \(keyframes.count))")
        }
        for (index, keyframe) in keyframes.enumerated() {
            guard keyframe.atMs.isFinite, keyframe.angle.isFinite else {
                throw fail("keyframe \(index) has a non-finite value")
            }
            guard (0...180).contains(keyframe.angle) else {
                throw fail("keyframe \(index) angle must be in 0...180 (got \(keyframe.angle))")
            }
            if index == 0, keyframe.atMs != 0 { throw fail("the first atMs must be 0 (got \(keyframe.atMs))") }
            if index > 0, keyframe.atMs <= keyframes[index - 1].atMs {
                throw fail(
                    "atMs must be strictly ascending (keyframe \(index) is \(keyframe.atMs) "
                        + "after \(keyframes[index - 1].atMs))"
                )
            }
        }
        guard let last = keyframes.last, last.atMs <= Self.maxDurationMs else {
            throw fail("the last atMs must be at most \(Int(Self.maxDurationMs)) (60 s)")
        }
        self.keyframes = keyframes
    }

    /// The angle at `ms` after the start, linearly interpolated; clamped to the first and last keyframe.
    public func angle(atMs ms: Double) -> Double {
        guard let first = keyframes.first, let last = keyframes.last else { return 0 }
        if ms <= first.atMs { return first.angle }
        if ms >= last.atMs { return last.angle }
        for (previous, next) in zip(keyframes, keyframes.dropFirst()) where ms <= next.atMs {
            let fraction = (ms - previous.atMs) / (next.atMs - previous.atMs)
            return previous.angle + (next.angle - previous.angle) * fraction
        }
        return last.angle
    }

    /// Frame n is due at n/60 s (computed from n, never accumulated), from n = 0 up to the last whole frame inside the
    /// motion; the final frame always sits exactly at the last keyframe, so the hinge ends at its commanded angle.
    public var frames: [HingeFrame] {
        let durationSeconds = durationMs / 1000
        let wholeFrames = Int((durationSeconds * Self.frameRate + 1e-9).rounded(.down))
        var result = (0...wholeFrames).map { n -> HingeFrame in
            let offset = Double(n) / Self.frameRate
            return HingeFrame(offset: offset, angle: angle(atMs: offset * 1000))
        }
        if let lastOffset = result.last?.offset, durationSeconds - lastOffset > 1e-6 {
            result.append(HingeFrame(offset: durationSeconds, angle: finalAngle))
        }
        return result
    }
}

/// Monotonic seconds and a sleep that ends at an absolute time. Tests substitute a fake that advances on sleep.
public protocol FrameClock {
    func now() -> TimeInterval
    /// Returns once `now() >= deadline` (immediately when it already is).
    func sleep(until deadline: TimeInterval)
}

/// `mach_absolute_time` seconds and `mach_wait_until`, as `Fold.m` paced its frames.
public struct MachFrameClock: FrameClock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public init() {}

    private var nanosPerTick: Double { Double(Self.timebase.numer) / Double(Self.timebase.denom) }

    public func now() -> TimeInterval { Double(mach_absolute_time()) * nanosPerTick / 1e9 }

    public func sleep(until deadline: TimeInterval) {
        guard deadline > now() else { return }
        mach_wait_until(UInt64(deadline * 1e9 / nanosPerTick))
    }
}

/// Where hinge angles go: the guest's `stream` verb in real runs, a recorder in tests.
public protocol HingeSending {
    func send(angle: Double) throws
}

/// A screen recording that brackets the motion.
public protocol VideoRecording {
    func start() throws
    func stop() throws
}

public struct KeyframePlayback: Sendable, Equatable {
    public var frames: Int
    public var durationSeconds: TimeInterval
    /// The worst a frame was late against its absolute deadline, in milliseconds.
    public var maxLatenessMs: Double
}

public struct KeyframesResult: Sendable, Equatable {
    public var playback: KeyframePlayback
    public var fold: FoldResult
    public var recording: String?

    public var summary: String {
        let angle = fold.reading.angleDegrees
        let angleText = angle == angle.rounded() ? String(Int(angle)) : String(angle)
        var line =
            "fold keyframes: \(playback.frames) frames over \(Int((playback.durationSeconds * 1000).rounded())) ms "
            + "(max lateness \(String(format: "%.1f", playback.maxLatenessMs)) ms), "
            + "final hinge \(angleText) deg (\(fold.reading.pose.rawValue)), lit panel \(fold.litPanel)"
        if let recording { line += "\nrecorded \(recording)" }
        return line
    }
}

public enum Keyframes {
    /// How long the recording runs on after the last frame, so the movie ends on the settled pose.
    public static let recordingTail: TimeInterval = 0.3

    /// Sends every frame at start + offset (absolute deadlines: a slow send makes the next frames late, never shifts
    /// them). The recorder starts before the first frame and stops `tail` after the last, also when a send fails.
    public static func play(
        plan: KeyframePlan,
        sender: any HingeSending,
        recorder: (any VideoRecording)? = nil,
        clock: any FrameClock = MachFrameClock(),
        tail: TimeInterval = Keyframes.recordingTail
    ) throws -> KeyframePlayback {
        let frames = plan.frames
        var worst = 0.0
        try recorder?.start()
        let begin = clock.now()
        var failure: (any Error)?
        do {
            for frame in frames {
                let deadline = begin + frame.offset
                clock.sleep(until: deadline)
                worst = max(worst, (clock.now() - deadline) * 1000)
                try sender.send(angle: frame.angle)
            }
        } catch {
            failure = error
        }
        if let recorder {
            clock.sleep(until: clock.now() + tail)
            do { try recorder.stop() } catch { failure = failure ?? error }
        }
        if let failure { throw failure }
        return KeyframePlayback(frames: frames.count, durationSeconds: frames.last?.offset ?? 0, maxLatenessMs: worst)
    }

    /// Plays the plan through the guest's `stream` verb, then proves the final pose like `duo fold` does.
    public static func run(
        plan: KeyframePlan,
        udid: String,
        guestPath: String,
        record: String? = nil,
        recordDisplay: DisplaySelector = .lit,
        runner: any ProcessRunning = SystemProcessRunner(),
        clock: any FrameClock = MachFrameClock(),
        now: () -> Date = Date.init,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws -> KeyframesResult {
        guard let target = FoldTarget.parse(String(plan.finalAngle)) else {
            throw DuoError.verificationFailed("--keyframes: final angle \(plan.finalAngle) is not a hinge angle")
        }
        // One movie records one display (simctl refuses to guess on the Duo), the one `recordDisplay` names right now.
        let recorder = try record.map { path in
            SimctlRecorder(
                udid: udid,
                path: path,
                displayName: try Screenshot.resolveDisplay(udid: udid, selector: recordDisplay, runner: runner).name
            )
        }
        let stream = try GuestHingeStream(udid: udid, guestPath: guestPath)
        // An interrupt must not orphan `recordVideo` or leave the guest streaming.
        let signals = KeyframeSignalGuard { number in
            recorder?.interrupt()
            stream.closeInput()
            FileHandle.standardError.write(
                Data("duo: interrupted; the hinge may be mid-motion: run ./dev pose closed-portrait\n".utf8)
            )
            exit(128 + number)
        }
        defer { signals.cancel() }
        let playback: KeyframePlayback
        do {
            playback = try play(plan: plan, sender: stream, recorder: recorder, clock: clock)
        } catch {
            _ = try? stream.finish()
            throw error
        }
        try stream.finish()
        let fold = try Fold.verify(
            target: target,
            udid: udid,
            guestPath: guestPath,
            png: nil,
            runner: runner,
            now: now,
            sleep: sleep
        )
        return KeyframesResult(playback: playback, fold: fold, recording: record)
    }
}

// MARK: - Real processes

/// A flag set from another thread (readability and termination handlers).
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// The temp file a long-lived child writes its stderr to (a file, not a pipe: nothing to drain, nothing to deadlock on).
private struct StderrFile {
    let url: URL
    let handle: FileHandle

    init(directory: URL) throws {
        url = directory.appendingPathComponent("duo-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        do {
            handle = try FileHandle(forWritingTo: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    var text: String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

    /// Idempotent: safe on every exit path and again from `deinit`.
    func remove() {
        try? handle.close()
        try? FileManager.default.removeItem(at: url)
    }
}

/// `xcrun simctl spawn <udid> <guest> stream`, kept open for the whole motion; each angle is one line on its stdin.
public final class GuestHingeStream: HingeSending, @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let stderrFile: StderrFile
    private let lock = NSLock()
    private var closed = false

    /// The stderr temp file; internal so tests can prove it is gone.
    var errorURL: URL { stderrFile.url }

    public static func arguments(udid: String, guestPath: String) -> [String] {
        ["simctl", "spawn", udid, guestPath, "stream"]
    }

    /// Starts the guest and waits for its ready line (up to `readyTimeout` s), so frame 0 is not held back by launch.
    /// The wait ends on the ready line, on EOF or on the process exiting; an exit throws `commandFailed` with its
    /// stderr at once. `executable`/`arguments` default to xcrun and `arguments(udid:guestPath:)`; tests inject stand-ins.
    public init(
        udid: String,
        guestPath: String,
        readyTimeout: TimeInterval = 15,
        executable: String = "/usr/bin/xcrun",
        arguments: [String]? = nil,
        scratch: URL = FileManager.default.temporaryDirectory
    ) throws {
        signal(SIGPIPE, SIG_IGN)  // a dead guest must surface as a write error, not kill duo
        stderrFile = try StderrFile(directory: scratch)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments ?? Self.arguments(udid: udid, guestPath: guestPath)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = stderrFile.handle

        let wake = DispatchSemaphore(value: 0)
        let exited = DispatchSemaphore(value: 0)
        let sawReady = Flag()
        process.terminationHandler = { _ in
            exited.signal()
            wake.signal()
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData  // empty = EOF
            handle.readabilityHandler = nil
            if !data.isEmpty { sawReady.set() }  // the ready JSON; nothing else matters
            wake.signal()
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            stderrFile.remove()
            throw error
        }

        let timedOut = wake.wait(timeout: .now() + readyTimeout) == .timedOut
        output.fileHandleForReading.readabilityHandler = nil
        if timedOut {
            process.terminate()
            stderrFile.remove()
            throw DuoError.timedOut(
                command: "xcrun simctl spawn … duo-guest stream (ready)",
                seconds: readyTimeout
            )
        }
        if sawReady.isSet { return }
        // EOF or exit without a ready line: the guest is gone (or going); its stderr says why.
        if exited.wait(timeout: .now() + 2) == .timedOut { process.terminate() }
        let status = process.isRunning ? Int32(-1) : process.terminationStatus
        let detail = stderrFile.text
        stderrFile.remove()
        throw DuoError.commandFailed(
            command: "xcrun simctl spawn … duo-guest stream",
            status: status,
            stderr: detail
        )
    }

    deinit { stderrFile.remove() }

    public func send(angle: Double) throws {
        do {
            try input.fileHandleForWriting.write(contentsOf: Data("\(angle)\n".utf8))
        } catch {
            throw DuoError.commandFailed(
                command: "xcrun simctl spawn … duo-guest stream",
                status: process.isRunning ? -1 : process.terminationStatus,
                stderr: stderrFile.text
            )
        }
    }

    /// Closes stdin (the guest exits at end of input). Idempotent; also what a signal handler calls.
    public func closeInput() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        try? input.fileHandleForWriting.close()
    }

    /// Closes stdin and checks the guest exited cleanly.
    public func finish(timeout: TimeInterval = 10) throws {
        closeInput()
        defer { stderrFile.remove() }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            throw DuoError.timedOut(
                command: "xcrun simctl spawn … duo-guest stream (exit)",
                seconds: timeout
            )
        }
        guard process.terminationStatus == 0 else {
            throw DuoError.commandFailed(
                command: "xcrun simctl spawn … duo-guest stream",
                status: process.terminationStatus,
                stderr: stderrFile.text
            )
        }
    }
}

/// `xcrun simctl io <udid> recordVideo --display=<name> --force <path>`: read-only on the display. Stopped with SIGINT, which makes
/// simctl finalise the movie, and waited for.
public final class SimctlRecorder: VideoRecording, @unchecked Sendable {
    public let path: String
    private let udid: String
    private let displayName: String
    private let executable: String
    private let argumentOverride: [String]?
    private let process = Process()
    private let stderrFile: StderrFile?

    public static func arguments(udid: String, displayName: String, path: String) -> [String] {
        ["simctl", "io", udid, "recordVideo", "--display=\(displayName)", "--force", path]
    }

    /// `executable`/`arguments` default to xcrun and `arguments(udid:displayName:path:)`; tests inject stand-ins.
    public init(
        udid: String,
        path: String,
        displayName: String,
        executable: String = "/usr/bin/xcrun",
        arguments: [String]? = nil,
        scratch: URL = FileManager.default.temporaryDirectory
    ) {
        self.udid = udid
        self.path = path
        self.displayName = displayName
        self.executable = executable
        self.argumentOverride = arguments
        stderrFile = try? StderrFile(directory: scratch)
    }

    deinit { stderrFile?.remove() }

    var isRunning: Bool { process.isRunning }

    private var commandArguments: [String] {
        argumentOverride ?? Self.arguments(udid: udid, displayName: displayName, path: path)
    }

    /// Launches the recorder and waits until it says it is recording (its stderr gets "Recording started").
    public func start() throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = commandArguments
        process.standardError = stderrFile?.handle ?? FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(15)
        while true {
            if stderrText().contains("Recording started") { return }
            if !process.isRunning || Date() >= deadline { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        let detail = stderrText()
        let status = process.isRunning ? Int32(-1) : process.terminationStatus
        if process.isRunning { process.terminate() }
        stderrFile?.remove()
        throw DuoError.commandFailed(
            command: "xcrun " + commandArguments.joined(separator: " "),
            status: status,
            stderr: detail
        )
    }

    public func stop() throws {
        try stop(timeout: 20)
    }

    /// Finalises the movie. A recorder that already died with a failure status is reported with its stderr, and so is
    /// a missing or empty movie: success means a non-empty file at `path`.
    func stop(timeout: TimeInterval) throws {
        defer { stderrFile?.remove() }
        let command = "xcrun " + commandArguments.joined(separator: " ")
        if process.isRunning {
            kill(process.processIdentifier, SIGINT)
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning {
                process.terminate()
                throw DuoError.timedOut(
                    command: "xcrun simctl io … recordVideo (finalise)",
                    seconds: timeout
                )
            }
        } else if process.terminationStatus != 0 {
            // It died on its own before the stop (refused display, crash, killed). After our own SIGINT the exit
            // status is simctl's business; the movie check below is what proves that case.
            throw DuoError.commandFailed(
                command: command,
                status: process.terminationStatus,
                stderr: stderrText()
            )
        }
        let size =
            (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else {
            throw DuoError.commandFailed(
                command: command,
                status: process.terminationStatus,
                stderr: stderrText() + "\nno recording at \(path) (missing or empty)"
            )
        }
    }

    /// For a signal handler: SIGINT the recorder and give it a moment to finalise. Never throws.
    func interrupt(timeout: TimeInterval = 5) {
        guard process.isRunning else { return }
        try? stop(timeout: timeout)
    }

    private func stderrText() -> String { stderrFile?.text ?? "" }
}

/// SIGINT/SIGTERM handling for a keyframe run: the signal stops the recorder (so the movie is finalised), closes the
/// guest's stdin (so it exits) and ends `duo` with 128 + the signal. SIGKILL cannot be handled.
final class KeyframeSignalGuard: @unchecked Sendable {
    private var sources: [any DispatchSourceSignal] = []
    private var previous: [(Int32, sig_t?)] = []

    init(signals: [Int32] = [SIGINT, SIGTERM], onSignal: @escaping @Sendable (Int32) -> Void) {
        for number in signals {
            let old = signal(number, SIG_IGN)  // the dispatch source takes over delivery
            previous.append((number, old))
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { onSignal(number) }
            source.resume()
            sources.append(source)
        }
    }

    func cancel() {
        for source in sources { source.cancel() }
        sources = []
        for (number, old) in previous { signal(number, old ?? SIG_DFL) }
        previous = []
    }
}
