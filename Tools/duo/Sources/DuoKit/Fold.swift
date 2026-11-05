import Foundation

/// What `duo fold` was asked for: a named pose or an explicit angle.
public struct FoldTarget: Sendable, Equatable {
    /// The argument as typed; it is passed on to the guest unchanged.
    public var argument: String
    public var angle: Double
    public var pose: Pose

    public static let presets: [String: Double] = ["closed": 0, "half-open": 130, "open": 180]

    public static func parse(_ argument: String) -> FoldTarget? {
        if let angle = presets[argument] {
            return FoldTarget(argument: argument, angle: angle, pose: Pose.classify(angleDegrees: angle))
        }
        guard let angle = Double(argument), angle.isFinite, (0...180).contains(angle) else { return nil }
        return FoldTarget(argument: argument, angle: angle, pose: Pose.classify(angleDegrees: angle))
    }

    /// Whether one hinge reading is in this target's category (stability is checked across readings, not here).
    /// The simulator settles at its own angle (a commanded 130 deg holds near 123 deg), so an explicit angle is
    /// verified by category like the named poses, and the reached angle is reported.
    public func accepts(_ reading: HingeReading) -> Bool {
        reading.angleValid && reading.pose == pose
    }

    /// The panel that must be lit once the target is reached: the cover panel when closed, else the inner one.
    public var expectedPanel: DisplaySelector { pose == .closed ? .outer : .inner }
}

/// Outcome of the read loop.
public struct PoseVerification: Sendable, Equatable {
    public var reached: Bool
    public var reads: [HingeReading]

    public var last: HingeReading? { reads.last }
}

/// Reads the hinge until it agrees with the target. Pure: the reads come from a closure, so tests script them.
public enum PoseVerifier {
    public static let maxReads = 8
    /// Consecutive half-open reads must agree within this many degrees.
    public static let stability = 0.5
    /// First read is immediate; later reads sample a second later so a moving hinge shows up as movement.
    public static let laterWindowMs = 1000

    public static func verify(
        target: FoldTarget,
        maxReads: Int = PoseVerifier.maxReads,
        read: (_ windowMs: Int) throws -> HingeReading
    ) throws -> PoseVerification {
        var reads: [HingeReading] = []
        for index in 0..<maxReads {
            let reading = try read(index == 0 ? 0 : laterWindowMs)
            reads.append(reading)
            guard target.accepts(reading) else { continue }
            // Closed and open are end stops; only a position in between can still be drifting.
            guard target.pose == .halfOpen else { return PoseVerification(reached: true, reads: reads) }
            if reads.count >= 2, let previous = reads.dropLast().last, target.accepts(previous),
                abs(previous.angleDegrees - reading.angleDegrees) <= stability
            {
                return PoseVerification(reached: true, reads: reads)
            }
        }
        return PoseVerification(reached: false, reads: reads)
    }
}

/// Waits for the documented panel state that goes with a pose. Pure over its closures: the clock and the
/// sleep are injected, so tests advance time without waiting.
public enum PanelCheck {
    /// The panel switch trails the hinge by several seconds, with both panels dark in between.
    public static let timeout: TimeInterval = 20

    public static func waitFor(
        expected: DisplaySelector,
        timeout: TimeInterval = PanelCheck.timeout,
        interval: TimeInterval = 0.5,
        now: () -> Date = Date.init,
        displays: () throws -> [Display],
        sleep: (TimeInterval) -> Void
    ) throws -> (expected: Display, lit: Display?, matched: Bool) {
        let deadline = now().addingTimeInterval(timeout)
        var table = try displays()
        let wanted = try expected.resolve(in: table)
        while true {
            if let lit = try? Panels.litPanel(in: table), lit.name == wanted.name {
                return (wanted, lit, true)
            }
            guard now() < deadline else { return (wanted, try? Panels.litPanel(in: table), false) }
            sleep(interval)
            table = try displays()
        }
    }
}

extension Simctl {
    /// `xcrun simctl spawn <udid> <guest> set <closed|half-open|open|degrees>`
    public static func setArguments(udid: String, guestPath: String, argument: String) -> [String] {
        ["simctl", "spawn", udid, guestPath, "set", argument]
    }

    public func setHinge(udid: String, guestPath: String, argument: String) throws {
        let arguments = Simctl.setArguments(udid: udid, guestPath: guestPath, argument: argument)
        let output = try runner.run("/usr/bin/xcrun", arguments: arguments)
        guard output.status == 0 else {
            throw DuoError.commandFailed(
                command: "xcrun simctl spawn … duo-guest set \(argument)",
                status: output.status,
                stderr: output.stderr
            )
        }
    }
}

public struct FoldResult: Sendable, Equatable {
    public var target: FoldTarget
    public var reading: HingeReading
    public var litPanel: String
    public var screenshot: ScreenshotResult?

    public var summary: String {
        let angle = reading.angleDegrees
        let angleText = angle == angle.rounded() ? String(Int(angle)) : String(angle)
        let line = "fold \(target.argument): hinge \(angleText) deg (\(reading.pose.rawValue)), lit panel \(litPanel)"
        guard let screenshot else { return line }
        return line + "\n" + screenshot.summary
    }
}

public enum Fold {
    /// Dispatches the hinge angle, then proves it with documented reads: hinge readings, then the lit panel.
    public static func run(
        target: FoldTarget,
        udid: String,
        guestPath: String,
        png: String? = nil,
        runner: any ProcessRunning = SystemProcessRunner(),
        now: () -> Date = Date.init,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws -> FoldResult {
        let simctl = Simctl(runner: runner)
        let devicectl = Devicectl(runner: runner)
        try simctl.setHinge(udid: udid, guestPath: guestPath, argument: target.argument)

        let verification = try PoseVerifier.verify(target: target) { window in
            try simctl.hinge(udid: udid, guestPath: guestPath, windowMs: window)
        }
        guard verification.reached, let reading = verification.last else {
            let lit = (try? Panels.litPanel(in: devicectl.displays(udid: udid)).name) ?? "unresolved"
            let seen = verification.reads.map { "\($0.angleDegrees)" }.joined(separator: ", ")
            throw DuoError.verificationFailed(
                "fold \(target.argument) not reached: hinge \(verification.last?.angleDegrees ?? .nan) deg "
                    + "after \(verification.reads.count) reads (\(seen)), lit panel \(lit); see docs/plan-device-tool.md 1.4"
            )
        }

        let panel = try PanelCheck.waitFor(
            expected: target.expectedPanel,
            now: now,
            displays: { try devicectl.displays(udid: udid) },
            sleep: sleep
        )
        guard panel.matched, let lit = panel.lit else {
            let actual = panel.lit?.name ?? "none"
            throw DuoError.verificationFailed(
                "fold \(target.argument): hinge \(reading.angleDegrees) deg (\(reading.pose.rawValue)) "
                    + "but lit panel \(actual), expected \(panel.expected.name)"
            )
        }

        var shot: ScreenshotResult?
        if let png {
            shot = try Screenshot.capture(path: png, udid: udid, selector: .lit, runner: runner)
        }
        return FoldResult(target: target, reading: reading, litPanel: lit.name, screenshot: shot)
    }
}
