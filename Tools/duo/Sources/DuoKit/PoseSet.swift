import Foundation

/// What `duo poses` did: one summary line per pose that completed, and how the set ended.
public struct PoseSetReport: Sendable {
    /// `<name>: <path> 1398x2034 px (466x678 pt, LCD)`, one per pose that got its PNG, in order.
    public var lines: [String]
    /// The first error in the set (nil when every pose succeeded).
    public var failure: (any Error)?
    /// The error from restoring closed-portrait afterwards (nil when it worked).
    public var restoreFailure: (any Error)?

    public var succeeded: Bool { failure == nil && restoreFailure == nil }

    /// The message for stderr when the set did not succeed; nil on success.
    public var failureMessage: String? {
        var parts: [String] = []
        if let failure { parts.append("\(failure)") }
        if let restoreFailure { parts.append("restoring closed-portrait also failed: \(restoreFailure)") }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }
}

/// The four layouts in a row, each as a settled PNG, ending where it started.
public enum PoseSet {
    /// The order the poses run in (the order of `NamedPose.allCases`).
    public static var order: [NamedPose] { NamedPose.allCases }

    public static func path(in directory: String, for pose: NamedPose) -> String {
        URL(fileURLWithPath: directory).appendingPathComponent(pose.rawValue + ".png").path
    }

    /// Runs the four poses in order into `<directory>/<name>.png` (settled captures), then restores closed-portrait.
    /// The restore also runs after a failure midway: the set stops at the first failing pose, restores, and reports
    /// both (the caller exits non-zero when `succeeded` is false). The restore takes no PNG.
    public static func run(
        directory: String,
        udid: String,
        guestPath: String,
        settle: TimeInterval = Settle.defaultTimeout,
        runner: any ProcessRunning = SystemProcessRunner(),
        now: () -> Date = Date.init,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) -> PoseSetReport {
        var report = PoseSetReport(lines: [])
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for pose in order {
                let result = try PoseCommand.run(
                    pose: pose,
                    udid: udid,
                    guestPath: guestPath,
                    png: path(in: directory, for: pose),
                    settle: settle,
                    runner: runner,
                    now: now,
                    sleep: sleep
                )
                guard let shot = result.orient.screenshot else {
                    throw DuoError.verificationFailed("\(pose.rawValue) took no screenshot")
                }
                report.lines.append("\(pose.rawValue): \(shot.summary)")
            }
        } catch {
            report.failure = error
        }
        do {
            _ = try PoseCommand.run(
                pose: .closedPortrait,
                udid: udid,
                guestPath: guestPath,
                runner: runner,
                now: now,
                sleep: sleep
            )
        } catch {
            report.restoreFailure = error
        }
        return report
    }
}
