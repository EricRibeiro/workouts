import Foundation
import SwiftData

/// Reads the finished history off the main thread (PLAN 6.4): the Exercises best-set texts and the History tab's rows
/// and Recent PRs card. Both walk every finished workout, its exercise rows and their sets, and every row and set read
/// is a SwiftData fault; with a few hundred workouts that blocked the main thread for around a second when the tab
/// opened. A `@ModelActor` owns its own `ModelContext` on the same container, does the walk there and hands back
/// Sendable values only, never models.
///
/// The context reads the store, so the caller saves the main context first (`ModelContext.save()`) when it has changes.
/// Build a reader per refresh instead of keeping one: a fresh context never serves a stale object.
@ModelActor
public actor WorkoutStatsReader {
    /// The finished workouts, newest first, with their exercise rows prefetched. The sets fault on the way through.
    private func finishedWorkouts() throws -> [Workout] {
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.finishedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.exercises]
        return try modelContext.fetch(descriptor)
    }

    /// `ExerciseBestSets.texts` for every exercise in the finished history. `weightTypes` is the exercise id to weight
    /// type lookup (`ExerciseStore.weightTypes`); ids it lacks are `.weighted`, as in the synchronous path.
    public func bestSetTexts(weightTypes: [UUID: WeightType], options: RecordsOptions) throws -> [UUID: String] {
        let sessions = ExerciseBestSets.sessions(from: try finishedWorkouts()) { weightTypes[$0] }
        return ExerciseBestSets.texts(from: sessions, options: options)
    }

    /// `HistoryDashboard.build` over the finished history: the History rows and the Recent PRs card.
    public func historySummary(
        weightTypes: [UUID: WeightType],
        options: RecordsOptions,
        limit: Int = 3
    ) throws -> HistorySummary {
        HistoryDashboard.build(
            from: try finishedWorkouts(),
            weightType: { weightTypes[$0] },
            options: options,
            limit: limit
        )
    }

    // MARK: Off the main thread

    // A `ModelActor` created on the main actor runs on the main thread (its executor follows the thread that created
    // it), which is what these entry points avoid: `@concurrent` runs them on the global pool, and the reader is created
    // there. Call these from views; the instance methods above are what they wrap.

    /// `bestSetTexts(weightTypes:options:)` on a fresh reader created off the main actor.
    @concurrent
    public static func loadBestSetTexts(
        in container: ModelContainer,
        weightTypes: [UUID: WeightType],
        options: RecordsOptions
    ) async throws -> [UUID: String] {
        try await WorkoutStatsReader(modelContainer: container)
            .bestSetTexts(weightTypes: weightTypes, options: options)
    }

    /// `historySummary(weightTypes:options:limit:)` on a fresh reader created off the main actor.
    @concurrent
    public static func loadHistorySummary(
        in container: ModelContainer,
        weightTypes: [UUID: WeightType],
        options: RecordsOptions,
        limit: Int = 3
    ) async throws -> HistorySummary {
        try await WorkoutStatsReader(modelContainer: container)
            .historySummary(weightTypes: weightTypes, options: options, limit: limit)
    }
}
