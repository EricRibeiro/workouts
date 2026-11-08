import Foundation
import SwiftData

/// The one definition of "finished": `finishedAt != nil`. A workout without it is the in-progress one. Every filter,
/// `@Query` and `FetchDescriptor` over that rule builds on these, so the rule is written here and nowhere else.
extension Workout {
    /// In-memory form of ``finishedPredicate``, for `filter` and `where` over already-fetched workouts.
    public var isFinished: Bool { finishedAt != nil }

    /// Finished workouts: for `Query(filter:sort:)` and `FetchDescriptor(predicate:sortBy:)`.
    public static var finishedPredicate: Predicate<Workout> {
        #Predicate<Workout> { $0.finishedAt != nil }
    }

    /// The finished workout `id`.
    public static func finishedPredicate(id: UUID) -> Predicate<Workout> {
        #Predicate<Workout> { $0.id == id && $0.finishedAt != nil }
    }

    /// Finished workouts other than `id`.
    public static func finishedPredicate(excluding id: UUID) -> Predicate<Workout> {
        #Predicate<Workout> { $0.id != id && $0.finishedAt != nil }
    }

    /// Finished workouts that finished at or after `cutoff`.
    public static func finishedPredicate(since cutoff: Date) -> Predicate<Workout> {
        // Predicates cannot call `Date.distantPast`; a value just before the cutoff stands in for "never finished".
        let beforeCutoff = cutoff.addingTimeInterval(-1)
        return #Predicate<Workout> { workout in
            workout.finishedAt != nil && (workout.finishedAt ?? beforeCutoff) >= cutoff
        }
    }

    /// The in-progress workout (`finishedAt == nil`).
    public static var inProgressPredicate: Predicate<Workout> {
        #Predicate<Workout> { $0.finishedAt == nil }
    }

    /// The in-progress workout, newest start first, `fetchLimit` 1 (at most one should exist; strays are tolerated).
    public static var inProgress: FetchDescriptor<Workout> {
        var descriptor = FetchDescriptor<Workout>(
            predicate: inProgressPredicate,
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }
}

extension WorkoutExercise {
    /// Rows of the exercises `ids` that belong to a finished workout: Previous and PR history fetch these directly
    /// instead of walking every workout's `exercises`.
    public static func inFinishedWorkouts(ofExercises ids: Set<UUID>) -> Predicate<WorkoutExercise> {
        #Predicate<WorkoutExercise> { ids.contains($0.exerciseID) && $0.workout?.finishedAt != nil }
    }

    /// As ``inFinishedWorkouts(ofExercises:)``, leaving out the workout `id`.
    public static func inFinishedWorkouts(ofExercises ids: Set<UUID>, excluding id: UUID) -> Predicate<WorkoutExercise>
    {
        #Predicate<WorkoutExercise> {
            ids.contains($0.exerciseID) && $0.workout?.id != id && $0.workout?.finishedAt != nil
        }
    }
}
