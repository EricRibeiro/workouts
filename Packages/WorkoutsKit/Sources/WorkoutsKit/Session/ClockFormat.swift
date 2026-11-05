import Foundation

/// The one place a number of seconds becomes a clock string. Built on `Duration.formatted(.time(pattern:))` (en_US, so
/// the digits never follow the device locale); negative input clamps to 0.
public nonisolated enum ClockFormat {
    /// `seconds` as `m:ss`, or `h:mm:ss` from 3600 (`3600` is `1:00:00`).
    public static func clock(seconds: Int) -> String {
        let total = max(0, seconds)
        let duration = Duration.seconds(total)
        let locale = Locale(identifier: "en_US")
        if total >= 3600 {
            return duration.formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 1)).locale(locale))
        }
        return duration.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)).locale(locale))
    }

    /// `clock(seconds:)` for a fractional length, rounded to the nearest second.
    public static func clock(seconds: TimeInterval) -> String {
        clock(seconds: Int(max(0, seconds).rounded()))
    }

    /// `45 s` below a minute, `m:ss` from a minute on (`1:30`): how a set's duration reads.
    public static func compact(seconds: Int) -> String {
        let seconds = max(0, seconds)
        return seconds < 60 ? "\(seconds) s" : clock(seconds: seconds)
    }
}
