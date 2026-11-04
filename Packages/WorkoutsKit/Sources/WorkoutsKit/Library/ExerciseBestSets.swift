import Foundation

/// The best set of each exercise's most recent session, as the Exercises list shows it on the right of a row
/// (`docs/port/screens/exercises.md` section 2, "Row": warm-ups and unchecked sets never count).
public nonisolated enum ExerciseBestSets {
    /// One `Session` per finished workout and exercise row, completed sets only, grouped by exercise id.
    /// `weightType` resolves an exercise id to its weight type (unknown ids are `.weighted`).
    @MainActor
    public static func sessions(
        from workouts: [Workout],
        weightType: (UUID) -> WeightType?
    ) -> [UUID: [Session]] {
        var result: [UUID: [Session]] = [:]
        for workout in workouts where workout.finishedAt != nil {
            for row in workout.exercises ?? [] {
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
                result[row.exerciseID, default: []].append(
                    Session(
                        workoutID: workout.id,
                        time: workout.startedAt,
                        exerciseID: row.exerciseID,
                        weightType: weightType(row.exerciseID) ?? .weighted,
                        sets: sets
                    )
                )
            }
        }
        return result
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
