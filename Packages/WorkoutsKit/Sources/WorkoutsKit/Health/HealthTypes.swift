import Foundation

/// The Fitness activity type of a Health workout. Only the strength kinds are ever matched to one of our workouts.
public nonisolated enum HealthActivityKind: Codable, Hashable, Sendable {
    case functionalStrength
    case traditionalStrength
    /// Any other activity; the payload is a free-form name for diagnostics (e.g. "running").
    case other(String)

    /// True for the kinds that can be our workout (functional or traditional strength training).
    public var isStrength: Bool {
        switch self {
        case .functionalStrength, .traditionalStrength: true
        case .other: false
        }
    }
}

/// A workout found in Apple Health, before its details are read.
public nonisolated struct HealthWorkoutCandidate: Codable, Hashable, Sendable, Identifiable {
    /// The HealthKit workout's UUID string.
    public var id: String
    public var kind: HealthActivityKind
    public var start: Date
    public var end: Date
    /// Name of the recording source, e.g. "Eric's Apple Watch".
    public var sourceName: String?

    public init(
        id: String,
        kind: HealthActivityKind,
        start: Date,
        end: Date,
        sourceName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.sourceName = sourceName
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    public var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

/// One heart-rate sample on the chart: seconds since the Fitness workout's start, and beats per minute.
public nonisolated struct HeartRatePoint: Codable, Hashable, Sendable {
    public var offset: TimeInterval
    public var bpm: Double

    public init(offset: TimeInterval, bpm: Double) {
        self.offset = offset
        self.bpm = bpm
    }
}

/// What we keep from the matched Fitness workout.
public nonisolated struct HealthWorkoutSummary: Codable, Hashable, Sendable {
    /// The HealthKit workout's UUID string (kept so the same Fitness workout is never claimed twice).
    public var healthWorkoutID: String
    public var start: Date
    public var end: Date
    public var activeEnergyKcal: Double?
    /// Active plus resting energy, when Health has it.
    public var totalEnergyKcal: Double?
    public var avgHeartRate: Double?
    public var maxHeartRate: Double?
    /// Coarse series for a small chart; see `HeartRateSeries.downsample`.
    public var heartRateSeries: [HeartRatePoint]

    public init(
        healthWorkoutID: String,
        start: Date,
        end: Date,
        activeEnergyKcal: Double? = nil,
        totalEnergyKcal: Double? = nil,
        avgHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        heartRateSeries: [HeartRatePoint] = []
    ) {
        self.healthWorkoutID = healthWorkoutID
        self.start = start
        self.end = end
        self.activeEnergyKcal = activeEnergyKcal
        self.totalEnergyKcal = totalEnergyKcal
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.heartRateSeries = heartRateSeries
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}
