import Foundation

/// The orientations the simulator's orientation control accepts. It has no upside-down value.
public enum TargetOrientation: String, Sendable, CaseIterable {
    case portrait
    case landscapeLeft = "landscape-left"
    case landscapeRight = "landscape-right"

    /// `devicectl device orientation get` spelling.
    public var deviceName: String {
        switch self {
        case .portrait: "portrait"
        case .landscapeLeft: "landscapeLeft"
        case .landscapeRight: "landscapeRight"
        }
    }

    /// Quarter turns, in degrees, a panel rotates relative to its portrait rotation (measured on the Duo).
    var rotationDelta: Int {
        switch self {
        case .portrait: 0
        case .landscapeLeft: 270
        case .landscapeRight: 90
        }
    }

    /// The `currentOrientation` the lit panel reports in portrait. Measured on iPhone Duo (iOS 27.2): the cover
    /// panel (primary) is `rot0`; the inner panel is laid out a quarter turn from its native size, `rot90`.
    static func portraitRotation(of display: Display) -> Int {
        display.primary == true ? 0 : 90
    }

    /// The `currentOrientation` (`rot0`, `rot90`, `rot180`, `rot270`) this panel reports once rotated here.
    public func expectedRotation(of display: Display) -> String {
        "rot\((Self.portraitRotation(of: display) + rotationDelta) % 360)"
    }
}

/// What the documented reads said at one moment.
public struct OrientationObservation: Sendable, Equatable {
    public var deviceOrientation: String
    public var litPanel: Display?

    public init(deviceOrientation: String, litPanel: Display?) {
        self.deviceOrientation = deviceOrientation
        self.litPanel = litPanel
    }

    public func matches(_ target: TargetOrientation) -> Bool {
        guard deviceOrientation == target.deviceName, let litPanel else { return false }
        return litPanel.currentOrientation == target.expectedRotation(of: litPanel)
    }

    public var text: String {
        "device \(deviceOrientation), lit panel \(litPanel?.name ?? "none") \(litPanel?.currentOrientation ?? "?")"
    }
}

public struct OrientationVerification: Sendable, Equatable {
    public var reached: Bool
    public var last: OrientationObservation?
    public var polls: Int
}

/// Polls the documented reads until the device orientation and the lit panel agree with the target.
/// Pure over its closures, so tests script the sequence and the sleep.
public enum OrientationVerifier {
    public static func verify(
        target: TargetOrientation,
        attempts: Int = 24,
        interval: TimeInterval = 0.5,
        observe: () throws -> OrientationObservation,
        sleep: (TimeInterval) -> Void
    ) throws -> OrientationVerification {
        var last: OrientationObservation?
        for attempt in 0..<attempts {
            if attempt > 0 { sleep(interval) }
            let observation = try observe()
            last = observation
            if observation.matches(target) {
                return OrientationVerification(reached: true, last: observation, polls: attempt + 1)
            }
        }
        return OrientationVerification(reached: false, last: last, polls: attempts)
    }
}

private struct OrientationDocument: Decodable {
    struct Result: Decodable {
        var deviceOrientation: String
    }
    var result: Result
}

extension Devicectl {
    /// `xcrun devicectl device orientation get --device <udid> --json-output -` → `deviceOrientation`
    public func deviceOrientation(udid: String) throws -> String {
        let arguments = [
            "devicectl", "device", "orientation", "get", "--device", udid, "--json-output", "-", "--quiet",
        ]
        let command = "xcrun " + arguments.joined(separator: " ")
        let output = try runner.run("/usr/bin/xcrun", arguments: arguments)
        guard output.status == 0 else {
            throw DuoError.commandFailed(command: command, status: output.status, stderr: output.stderr)
        }
        return try Self.decodeDeviceOrientation(output.stdout, command: command)
    }

    public static func decodeDeviceOrientation(_ data: Data, command: String = "devicectl device orientation get")
        throws -> String
    {
        do {
            return try JSONDecoder().decode(OrientationDocument.self, from: data).result.deviceOrientation
        } catch {
            throw DuoError.undecodable(command: command, reason: String(describing: error))
        }
    }
}

extension Simctl {
    /// `xcrun simctl spawn <udid> <guest> rotate <portrait|landscape-left|landscape-right>`
    public static func rotateArguments(udid: String, guestPath: String, orientation: TargetOrientation) -> [String] {
        ["simctl", "spawn", udid, guestPath, "rotate", orientation.rawValue]
    }

    public func rotate(udid: String, guestPath: String, orientation: TargetOrientation) throws {
        let arguments = Simctl.rotateArguments(udid: udid, guestPath: guestPath, orientation: orientation)
        let output = try runner.run("/usr/bin/xcrun", arguments: arguments)
        guard output.status == 0 else {
            throw DuoError.commandFailed(
                command: "xcrun simctl spawn … duo-guest rotate \(orientation.rawValue)",
                status: output.status,
                stderr: output.stderr
            )
        }
    }
}

public struct OrientResult: Sendable, Equatable {
    public var target: TargetOrientation
    public var observation: OrientationObservation
    public var screenshot: ScreenshotResult?

    public var summary: String {
        let line = "orient \(target.rawValue): \(observation.text)"
        guard let screenshot else { return line }
        return line + "\n" + screenshot.summary
    }
}

public enum Orient {
    /// Dispatches the orientation, then proves it with documented reads, then the optional PNG.
    public static func run(
        target: TargetOrientation,
        udid: String,
        guestPath: String,
        png: String? = nil,
        runner: any ProcessRunning = SystemProcessRunner(),
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws -> OrientResult {
        let devicectl = Devicectl(runner: runner)
        try Simctl(runner: runner).rotate(udid: udid, guestPath: guestPath, orientation: target)
        let verification = try OrientationVerifier.verify(
            target: target,
            observe: {
                OrientationObservation(
                    deviceOrientation: try devicectl.deviceOrientation(udid: udid),
                    litPanel: try? Panels.litPanel(in: devicectl.displays(udid: udid))
                )
            },
            sleep: sleep
        )
        guard verification.reached, let observation = verification.last else {
            let seen = verification.last?.text ?? "nothing read"
            throw DuoError.verificationFailed(
                "orient \(target.rawValue) not reached after \(verification.polls) polls: \(seen); "
                    + "see docs/plan-device-tool.md 1.4"
            )
        }
        var shot: ScreenshotResult?
        if let png {
            shot = try Screenshot.capture(path: png, udid: udid, selector: .lit, runner: runner)
        }
        return OrientResult(target: target, observation: observation, screenshot: shot)
    }
}
