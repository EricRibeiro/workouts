import Foundation

/// The hinge as the app reports it: the last `hinge status=<name> angle=<degrees>` line the app logged (DEBUG launch
/// argument `-logHinge`, `Workouts/Debug/HingeLogger.swift`) under subsystem `com.ericribeiro.Workouts`, category `hinge`.
public struct AppHinge: Sendable, Equatable {
    /// `unknown`, `closed`, `partiallyOpen`, `fullyOpen` or `unavailable`.
    public var status: String
    /// Whole degrees; nil for `unavailable`.
    public var angleDegrees: Int?

    public init(status: String, angleDegrees: Int?) {
        self.status = status
        self.angleDegrees = angleDegrees
    }

    /// `status: fullyOpen, angle: 180`
    public var text: String {
        "status: \(status)" + (angleDegrees.map { ", angle: \($0)" } ?? "")
    }

    /// The last line of `log show` output that carries a hinge record; nil when there is none. Reads `status=` and
    /// `angle=` from the end of the line, so the compact style's timestamp, process and subsystem prefix never matter.
    public static func parse(logOutput: String) -> AppHinge? {
        for line in logOutput.split(whereSeparator: \.isNewline).reversed() {
            guard let marker = line.range(of: "hinge status=", options: .backwards) else { continue }
            let fields = line[marker.upperBound...].split(separator: " ")
            guard let status = fields.first, !status.isEmpty else { continue }
            let angle = fields.dropFirst().first { $0.hasPrefix("angle=") }.flatMap {
                Int($0.dropFirst("angle=".count))
            }
            return AppHinge(status: String(status), angleDegrees: angle)
        }
        return nil
    }

    /// `xcrun simctl spawn <udid> log show --last 5m --style compact --predicate '…'`
    public static func logArguments(udid: String, last: String = "5m") -> [String] {
        [
            "simctl", "spawn", udid, "log", "show", "--last", last, "--style", "compact",
            "--predicate", "subsystem == \"com.ericribeiro.Workouts\" AND category == \"hinge\"",
        ]
    }

    /// Reads the app's last reported hinge status; throws `DuoError.verificationFailed` with the way out when there is none.
    public static func read(udid: String, runner: any ProcessRunning = SystemProcessRunner()) throws -> AppHinge {
        let output = try runner.run("/usr/bin/xcrun", arguments: logArguments(udid: udid))
        guard output.status == 0 else {
            throw DuoError.commandFailed(
                command: "xcrun simctl spawn … log show",
                status: output.status,
                stderr: output.stderr
            )
        }
        guard let hinge = parse(logOutput: String(decoding: output.stdout, as: UTF8.self)) else {
            throw DuoError.verificationFailed(
                "no hinge line from the app in the last 5 minutes; launch it with ./dev run -- -logHinge "
                    + "(a DEBUG build) and move the hinge, since the app logs only status changes"
            )
        }
        return hinge
    }
}
