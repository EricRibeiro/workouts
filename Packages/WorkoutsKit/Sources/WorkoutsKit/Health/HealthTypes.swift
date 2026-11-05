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
    /// Workout effort (rated, else estimated); nil on older workouts or when Health has none.
    public var effort: HealthEffort?
    /// Time spent in each heart-rate zone; empty when Health has no zones.
    public var zones: [HeartRateZoneTime]
    public var weatherTemperatureCelsius: Double?
    public var weatherHumidityPercent: Double?
    /// Identifier of the time zone the workout was recorded in (e.g. "Europe/Lisbon").
    public var timeZoneIdentifier: String?
    /// Everything else HealthKit returned, kept so later features need no schema change.
    public var details: HealthWorkoutDetails?

    public init(
        healthWorkoutID: String,
        start: Date,
        end: Date,
        activeEnergyKcal: Double? = nil,
        totalEnergyKcal: Double? = nil,
        avgHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        heartRateSeries: [HeartRatePoint] = [],
        effort: HealthEffort? = nil,
        zones: [HeartRateZoneTime] = [],
        weatherTemperatureCelsius: Double? = nil,
        weatherHumidityPercent: Double? = nil,
        timeZoneIdentifier: String? = nil,
        details: HealthWorkoutDetails? = nil
    ) {
        self.healthWorkoutID = healthWorkoutID
        self.start = start
        self.end = end
        self.activeEnergyKcal = activeEnergyKcal
        self.totalEnergyKcal = totalEnergyKcal
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.heartRateSeries = heartRateSeries
        self.effort = effort
        self.zones = zones
        self.weatherTemperatureCelsius = weatherTemperatureCelsius
        self.weatherHumidityPercent = weatherHumidityPercent
        self.timeZoneIdentifier = timeZoneIdentifier
        self.details = details
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Apple's workout effort: a 1-10 score, either rated by the person or estimated by Apple.
public nonisolated struct HealthEffort: Codable, Hashable, Sendable {
    public var score: Double
    public var isEstimated: Bool

    public init(score: Double, isEstimated: Bool) {
        self.score = score
        self.isEstimated = isEstimated
    }
}

/// Time spent in one heart-rate zone. Bounds are nil for the open ends (the first zone has no lower bound, the last
/// no upper bound) or when Health does not report them.
public nonisolated struct HeartRateZoneTime: Codable, Hashable, Sendable {
    /// Zone number as Health reports it (1-based, lowest effort first).
    public var index: Int
    public var lowerBPM: Double?
    public var upperBPM: Double?
    public var seconds: TimeInterval

    public init(index: Int, lowerBPM: Double? = nil, upperBPM: Double? = nil, seconds: TimeInterval) {
        self.index = index
        self.lowerBPM = lowerBPM
        self.upperBPM = upperBPM
        self.seconds = seconds
    }
}

/// One quantity type's statistics over the workout; each value is nil when the type does not offer it.
public nonisolated struct HealthStatistic: Codable, Hashable, Sendable {
    public var sum: Double?
    public var average: Double?
    public var minimum: Double?
    public var maximum: Double?
    public var mostRecent: Double?
    /// The unit the numbers are in (e.g. "kcal", "count/min").
    public var unit: String

    public init(
        sum: Double? = nil,
        average: Double? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        mostRecent: Double? = nil,
        unit: String
    ) {
        self.sum = sum
        self.average = average
        self.minimum = minimum
        self.maximum = maximum
        self.mostRecent = mostRecent
        self.unit = unit
    }
}

/// A typed time span: a workout event (pause, segment, lap...) or a workout activity.
public nonisolated struct HealthInterval: Codable, Hashable, Sendable {
    public var type: String
    public var start: Date
    public var end: Date

    public init(type: String, start: Date, end: Date) {
        self.type = type
        self.start = start
        self.end = end
    }
}

/// One point of the workout route.
public nonisolated struct HealthRoutePoint: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double?
    public var timestamp: Date

    public init(latitude: Double, longitude: Double, altitude: Double? = nil, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
    }
}

/// The versioned snapshot of everything HealthKit returned for the matched workout (PLAN 7.1b e4). Keyed by the
/// HealthKit identifiers, so a new key never needs a schema change. Decoding is lenient: a missing key reads as empty
/// and an unknown key is ignored, so older and newer builds can read each other's blobs.
public nonisolated struct HealthWorkoutDetails: Codable, Hashable, Sendable {
    public var version: Int
    /// Quantity type identifier -> statistics.
    public var statistics: [String: HealthStatistic]
    /// Metadata key -> value, already formatted as text by the reader.
    public var metadata: [String: String]
    public var events: [HealthInterval]
    public var activities: [HealthInterval]
    public var sourceName: String?
    public var sourceBundleID: String?
    public var deviceName: String?
    public var deviceModel: String?
    public var deviceHardwareVersion: String?
    public var deviceSoftwareVersion: String?
    public var route: [HealthRoutePoint]

    public init(
        version: Int = 1,
        statistics: [String: HealthStatistic] = [:],
        metadata: [String: String] = [:],
        events: [HealthInterval] = [],
        activities: [HealthInterval] = [],
        sourceName: String? = nil,
        sourceBundleID: String? = nil,
        deviceName: String? = nil,
        deviceModel: String? = nil,
        deviceHardwareVersion: String? = nil,
        deviceSoftwareVersion: String? = nil,
        route: [HealthRoutePoint] = []
    ) {
        self.version = version
        self.statistics = statistics
        self.metadata = metadata
        self.events = events
        self.activities = activities
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
        self.deviceName = deviceName
        self.deviceModel = deviceModel
        self.deviceHardwareVersion = deviceHardwareVersion
        self.deviceSoftwareVersion = deviceSoftwareVersion
        self.route = route
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        statistics = try c.decodeIfPresent([String: HealthStatistic].self, forKey: .statistics) ?? [:]
        metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        events = try c.decodeIfPresent([HealthInterval].self, forKey: .events) ?? []
        activities = try c.decodeIfPresent([HealthInterval].self, forKey: .activities) ?? []
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName)
        sourceBundleID = try c.decodeIfPresent(String.self, forKey: .sourceBundleID)
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName)
        deviceModel = try c.decodeIfPresent(String.self, forKey: .deviceModel)
        deviceHardwareVersion = try c.decodeIfPresent(String.self, forKey: .deviceHardwareVersion)
        deviceSoftwareVersion = try c.decodeIfPresent(String.self, forKey: .deviceSoftwareVersion)
        route = try c.decodeIfPresent([HealthRoutePoint].self, forKey: .route) ?? []
    }
}
