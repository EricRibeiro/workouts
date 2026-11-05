import Foundation

/// Where the hinge sits, as a category.
public enum Pose: String, Sendable, Equatable {
    case closed
    case halfOpen = "half-open"
    case open

    /// Degrees either side of 0 and 180 that still count as closed or open.
    public static let tolerance = 2.0

    public static func classify(angleDegrees angle: Double) -> Pose {
        if angle <= tolerance { return .closed }
        if angle >= 180 - tolerance { return .open }
        return .halfOpen
    }
}

/// One `duo-guest hinge` answer: `{"version":1,"angleDegrees":0,"angleValid":true}`.
public struct HingeReading: Sendable, Equatable, Decodable {
    public var angleDegrees: Double
    public var angleValid: Bool

    public init(angleDegrees: Double, angleValid: Bool) {
        self.angleDegrees = angleDegrees
        self.angleValid = angleValid
    }

    public var pose: Pose { Pose.classify(angleDegrees: angleDegrees) }

    public static func parse(_ data: Data) throws -> HingeReading {
        do {
            return try JSONDecoder().decode(HingeReading.self, from: data)
        } catch {
            throw DuoError.undecodable(command: "duo-guest hinge", reason: String(describing: error))
        }
    }
}

/// What `duo hinge` reports.
public struct HingeReport: Sendable, Equatable {
    public var reading: HingeReading
    /// Name of the lit panel; nil while zero or several panels are lit.
    public var litPanel: String?

    public init(reading: HingeReading, litPanel: String?) {
        self.reading = reading
        self.litPanel = litPanel
    }

    private var angleText: String {
        let value = reading.angleDegrees
        return value == value.rounded() ? String(Int(value)) : String(value)
    }

    /// `angleDegrees: 0, angleValid: true, pose: closed, litPanel: LCD`
    public var text: String {
        "angleDegrees: \(angleText), angleValid: \(reading.angleValid), pose: \(reading.pose.rawValue), "
            + "litPanel: \(litPanel ?? "unresolved")"
    }

    /// `{"angleDegrees":0,"angleValid":true,"litPanel":"LCD","pose":"closed"}`
    public var json: String {
        var object: [String: Any] = [
            "angleDegrees": reading.angleDegrees,
            "angleValid": reading.angleValid,
            "pose": reading.pose.rawValue,
        ]
        object["litPanel"] = litPanel ?? NSNull()
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

extension Simctl {
    /// `xcrun simctl spawn <udid> <guest> hinge <windowMs>`
    public static func hingeArguments(udid: String, guestPath: String, windowMs: Int) -> [String] {
        ["simctl", "spawn", udid, guestPath, "hinge", String(windowMs)]
    }

    /// Runs the in-simulator helper's `hinge` verb. Exit 3 and 4 carry the guest's own explanation on stderr.
    public func hinge(udid: String, guestPath: String, windowMs: Int = 0) throws -> HingeReading {
        let arguments = Simctl.hingeArguments(udid: udid, guestPath: guestPath, windowMs: windowMs)
        let output = try runner.run("/usr/bin/xcrun", arguments: arguments)
        guard output.status == 0 else {
            throw DuoError.commandFailed(
                command: "xcrun simctl spawn … duo-guest hinge",
                status: output.status,
                stderr: output.stderr
            )
        }
        return try HingeReading.parse(output.stdout)
    }
}

public enum Hinge {
    /// Builds (or reuses) the guest, reads the hinge, and names the lit panel.
    public static func read(
        udid: String,
        windowMs: Int = 0,
        guestPath: String,
        runner: any ProcessRunning = SystemProcessRunner()
    ) throws -> HingeReport {
        let reading = try Simctl(runner: runner).hinge(udid: udid, guestPath: guestPath, windowMs: windowMs)
        let displays = try Devicectl(runner: runner).displays(udid: udid)
        return HingeReport(reading: reading, litPanel: try? Panels.litPanel(in: displays).name)
    }
}
