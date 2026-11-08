import Foundation

/// The spoken strings of the rest ring and the resume ring. A rest that sits in its grace period (``RestTimer/expiredGraceSeconds``)
/// says "Rest over", never "0:00", which a VoiceOver user cannot tell apart from a rest about to end.
public nonisolated enum RestAccessibility {
    /// Posted as a VoiceOver announcement when a rest ends with the app in the foreground (the banner is suppressed there).
    public static let overAnnouncement = "Rest over"

    /// The rest ring's label: "Rest timer, 4:57" while it runs, "Rest over" once `remaining` reaches 0.
    public static func ringLabel(remaining: TimeInterval) -> String {
        remaining <= 0 ? overAnnouncement : "Rest timer, \(ClockFormat.clock(seconds: Int(remaining.rounded(.up))))"
    }

    /// The resume ring's state: "rest 4:57" while a rest runs, "rest over" in the grace, "12 minutes elapsed" otherwise.
    /// `endsAt` is the running rest's end, nil when no rest runs.
    public static func resumeState(startedAt: Date, endsAt: Date?, now: Date) -> String {
        if let endsAt {
            let remaining = endsAt.timeIntervalSince(now)
            if remaining <= 0 { return overAnnouncement.lowercased() }
            return "rest \(ClockFormat.clock(seconds: Int(remaining.rounded(.up))))"
        }
        return "\(elapsedPhrase(seconds: Int(now.timeIntervalSince(startedAt)))) elapsed"
    }

    /// "less than a minute", "1 minute", "12 minutes", "1 hour", "1 hour 5 minutes": minute granularity, because the idle
    /// resume label refreshes once a minute and a seconds readout would be stale the moment it is spoken.
    public static func elapsedPhrase(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes == 0 { return "less than a minute" }
        let hours = minutes / 60
        let rest = minutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if rest > 0 { parts.append(rest == 1 ? "1 minute" : "\(rest) minutes") }
        return parts.joined(separator: " ")
    }
}
