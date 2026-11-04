import Foundation

/// The logging screen's elapsed time (`formatElapsed` of the web app): `m:ss`, `h:mm:ss` from one hour.
public nonisolated enum ElapsedFormat {
    /// `seconds` as `m:ss`, or `h:mm:ss` from 3600 (`3600` is `1:00:00`). Negative clamps to 0.
    public static func string(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        let tail = rest < 10 ? "0\(rest)" : "\(rest)"
        if hours > 0 {
            let mm = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(mm):\(tail)"
        }
        return "\(minutes):\(tail)"
    }
}
