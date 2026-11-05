import Foundation

/// What to show for a workout's heart-rate zones: the full breakdown when the session spread across zones, else a
/// one-line caption.
public nonisolated struct ZoneSummary: Hashable, Sendable {
    public var zones: [HeartRateZoneTime]

    /// `zones` may be zero-based (older snapshots); they are repaired to one-based, sorted by zone.
    public init(zones: [HeartRateZoneTime]) {
        self.zones = HeartRateZoneTime.oneBased(zones).sorted { $0.index < $1.index }
    }

    public var totalSeconds: TimeInterval { zones.reduce(0) { $0 + max(0, $1.seconds) } }

    /// Time outside zone 1.
    public var secondsOutsideZone1: TimeInterval {
        zones.filter { $0.index != 1 }.reduce(0) { $0 + max(0, $1.seconds) }
    }

    /// True when the time outside zone 1 is at least 10 % of the total or at least 120 s.
    public var isMeaningful: Bool {
        let total = totalSeconds
        guard total > 0 else { return false }
        return secondsOutsideZone1 >= 120 || secondsOutsideZone1 / total >= 0.1
    }

    /// The zones that hold any time, in zone order.
    public var zonesWithTime: [HeartRateZoneTime] { zones.filter { $0.seconds > 0 } }

    /// `Zone 1 the whole time · up to 139 bpm`; nil when there is no time at all. When the time is not all in zone 1
    /// (but not enough to matter), names the zone that holds most of it.
    public var caption: String? {
        guard totalSeconds > 0, let dominant = zones.max(by: { $0.seconds < $1.seconds }) else { return nil }
        var text = "Zone \(dominant.index) the whole time"
        if let upper = dominant.upperBPM { text += " \u{00B7} up to \(FitnessFormat.wholeNumber(upper)) bpm" }
        return text
    }

    /// `Zone 2 · 8:45`: one legend entry.
    public static func legendText(_ zone: HeartRateZoneTime) -> String {
        "Zone \(zone.index) \u{00B7} \(FitnessFormat.clockText(seconds: zone.seconds))"
    }
}
