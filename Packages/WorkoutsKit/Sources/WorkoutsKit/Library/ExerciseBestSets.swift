import Foundation
import SwiftData

/// The best set of each exercise's most recent session, as the Exercises list shows it on the right of a row
/// (`docs/port/screens/exercises.md` section 2, "Row": warm-ups and unchecked sets never count).
public nonisolated enum ExerciseBestSets {
    /// One `Session` per finished workout and exercise row, completed sets only, grouped by exercise id.
    /// `weightType` resolves an exercise id to its weight type (unknown ids are `.weighted`). With `exerciseIDs`, only
    /// rows of those exercises are folded; the rest of the history is skipped rather than filtered afterwards.
    public static func sessions(
        from workouts: [Workout],
        weightType: (UUID) -> WeightType?,
        exerciseIDs: Set<UUID>? = nil
    ) -> [UUID: [Session]] {
        var result: [UUID: [Session]] = [:]
        for workout in workouts where workout.finishedAt != nil {
            for row in workout.exercises ?? [] {
                if let exerciseIDs, !exerciseIDs.contains(row.exerciseID) { continue }
                result[row.exerciseID, default: []].append(
                    session(row: row, workout: workout, weightType: weightType(row.exerciseID) ?? .weighted)
                )
            }
        }
        return result
    }

    /// The rows of one exercise in finished workouts, with their sets and workouts prefetched: what the exercise detail
    /// fetches (`@Query` or `ModelContext.fetch`) instead of every workout. Feed the result to `sessions(forRows:...)`.
    public static func rowsDescriptor(exerciseID: UUID) -> FetchDescriptor<WorkoutExercise> {
        var descriptor = FetchDescriptor<WorkoutExercise>(
            predicate: #Predicate { $0.exerciseID == exerciseID && $0.workout?.finishedAt != nil }
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.workout, \.sets]
        return descriptor
    }

    /// The sessions of one exercise, built from just that exercise's rows (the exercise detail fetches them with a
    /// predicate instead of walking every workout). Rows whose workout is missing or unfinished are skipped, as
    /// `sessions(from:weightType:exerciseIDs:)` does; the result is oldest first (the workout's start, then the row's
    /// position), and equals `sessions(from:...)[exerciseID]` for the same data in that order.
    @MainActor
    public static func sessions(forRows rows: [WorkoutExercise], weightType: WeightType) -> [Session] {
        rows.compactMap { row -> (WorkoutExercise, Workout)? in
            guard let workout = row.workout, workout.finishedAt != nil else { return nil }
            return (row, workout)
        }
        .sorted {
            ($0.1.startedAt, $0.0.position) < ($1.1.startedAt, $1.0.position)
        }
        .map { session(row: $0.0, workout: $0.1, weightType: weightType) }
    }

    /// Workout id to name for the workouts those rows belong to (the History segment's card titles).
    @MainActor
    public static func workoutNames(of rows: [WorkoutExercise]) -> [UUID: String] {
        Dictionary(
            rows.compactMap { row in row.workout.map { ($0.id, $0.name) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func session(row: WorkoutExercise, workout: Workout, weightType: WeightType) -> Session {
        let sets = (row.sets ?? []).filter(\.completed).sorted { $0.position < $1.position }.map {
            LoggedSet(
                kind: $0.kind,
                weight: $0.weight,
                unit: row.unit,
                reps: $0.reps,
                durationSeconds: $0.durationSeconds,
                distanceMeters: $0.distanceMeters,
                completed: $0.completed
            )
        }
        return Session(
            workoutID: workout.id,
            time: workout.startedAt,
            exerciseID: row.exerciseID,
            weightType: weightType,
            sets: sets
        )
    }

    /// The best set of the newest session that has a counted set, written in `options.displayUnit`: `100 kg × 5`,
    /// `12 reps`, `45 s`. Empty when the exercise was never performed.
    public static func text(for sessions: [Session], options: RecordsOptions) -> String {
        for session in sessions.sorted(by: { $0.time > $1.time }) {
            guard let best = bestSet(in: session.sets, weightType: session.weightType, options: options) else {
                continue
            }
            return formatSetDetail(
                weight: best.weightInDisplayUnit,
                unit: options.displayUnit,
                reps: best.set.reps,
                durationSeconds: best.set.durationSeconds
            )
        }
        return ""
    }

    /// `text(for:options:)` for every exercise id; exercises with nothing to show are left out.
    public static func texts(from sessions: [UUID: [Session]], options: RecordsOptions) -> [UUID: String] {
        sessions.compactMapValues { sessions in
            let text = text(for: sessions, options: options)
            return text.isEmpty ? nil : text
        }
    }
}
