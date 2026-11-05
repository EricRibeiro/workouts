import Foundation
import SwiftData

/// A workout. `finishedAt == nil` is the one in-progress workout. The rest-timer fields persist the running timer
/// across relaunch.
@Model
public final class Workout {
    public var id: UUID = UUID()
    public var name: String = ""
    public var note: String = ""
    public var startedAt: Date = Date()
    public var finishedAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    /// When the running rest timer ends; nil = no timer running.
    public var restEndsAt: Date?
    /// The length the running rest timer was started with.
    public var restSeconds: Int?
    /// The set whose completion started the running rest timer.
    public var restSetID: UUID?

    // Apple Fitness enrichment (PLAN 7.1b). Optional with nil defaults, so adding them is a lightweight migration and
    // stays CloudKit-compatible. Read and written through `healthSummary` / `applyHealth` (Health/WorkoutHealthFields).
    /// The matched HealthKit workout's UUID string; nil = not matched.
    public var healthWorkoutID: String?
    public var activeEnergyKcal: Double?
    public var totalEnergyKcal: Double?
    public var avgHeartRate: Double?
    public var maxHeartRate: Double?
    /// JSON of `[HeartRatePoint]` (a few dozen points, so stored inline).
    public var heartRateSeriesData: Data?
    /// The last time the app looked for a matching Fitness workout, so unmatched workouts are not re-queried endlessly.
    public var healthCheckedAt: Date?
    // More Fitness details (PLAN 7.1b e4), same pattern.
    public var effortScore: Double?
    public var effortIsEstimated: Bool?
    /// JSON of `[HeartRateZoneTime]`.
    public var heartRateZonesData: Data?
    public var weatherTemperatureCelsius: Double?
    public var weatherHumidityPercent: Double?
    /// Time zone identifier the Fitness workout was recorded in.
    public var healthTimeZone: String?
    /// JSON of `HealthWorkoutDetails`: the versioned snapshot of everything HealthKit returned.
    public var healthDetailsData: Data?

    /// Nil when the template was deleted (or the workout was started empty).
    public var template: Template?

    /// A workout takes its exercises and sets with it.
    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    public var exercises: [WorkoutExercise]? = []

    public init(
        id: UUID = UUID(),
        name: String = "",
        note: String = "",
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        template: Template? = nil,
        restEndsAt: Date? = nil,
        restSeconds: Int? = nil,
        restSetID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.template = template
        self.restEndsAt = restEndsAt
        self.restSeconds = restSeconds
        self.restSetID = restSetID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
