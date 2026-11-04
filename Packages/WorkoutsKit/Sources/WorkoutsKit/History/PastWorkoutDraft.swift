import Foundation
import SwiftData

/// The past-workout editor's working copy (task 5.6): plain values read from a finished `Workout`, edited freely, and
/// written back in one `save`. Nothing touches the model (or iCloud) until then, so Cancel is just dropping the draft.
///
/// The past editor has no check column, so completion is derived: on save a set with any value is completed, an empty set
/// is dropped, and an exercise left with no set goes with them (`history.md` section 3). Fields the editor does not show
/// (RPE, bar type, rest, `completedAt` of a kept set) stay on the model untouched because sets and exercises are matched
/// by id.
public struct PastWorkoutDraft: Equatable, Sendable {
    /// One set row of the draft.
    public struct SetValues: Equatable, Sendable, Identifiable {
        public let id: UUID
        public var kind: SetKind
        public var weight: Double?
        public var reps: Int?
        public var durationSeconds: Int?
        public var distanceMeters: Double?

        /// Whether the set records anything; a set without a value is dropped on save.
        public var hasValue: Bool {
            weight != nil || reps != nil || durationSeconds != nil || distanceMeters != nil
        }
    }

    /// One exercise block of the draft.
    public struct ExerciseValues: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let exerciseID: UUID
        public var name: String
        public var supersetGroup: Int?
        public var note: String
        public var unit: WeightUnit
        /// Whether the reps column holds seconds. Fixed when the draft is made, so clearing the one duration does not turn
        /// the block into a reps block mid-edit.
        public let isTimed: Bool
        public var sets: [SetValues]
    }

    public var name: String
    public var startedAt: Date
    public var exercises: [ExerciseValues]
    /// Never negative; set through `setDurationMinutes`.
    public private(set) var durationSeconds: Int

    /// The draft of a finished workout (a missing `finishedAt` reads as zero duration).
    public init(_ workout: Workout) {
        name = workout.name
        startedAt = workout.startedAt
        durationSeconds = max(0, Int((workout.finishedAt ?? workout.startedAt).timeIntervalSince(workout.startedAt)))
        exercises = (workout.exercises ?? [])
            .sorted { $0.position < $1.position }
            .map { row in
                let sets = (row.sets ?? []).sorted { $0.position < $1.position }
                return ExerciseValues(
                    id: row.id,
                    exerciseID: row.exerciseID,
                    name: row.exerciseName,
                    supersetGroup: row.supersetGroup,
                    note: row.note,
                    unit: row.unit,
                    isTimed: sets.contains { $0.durationSeconds != nil },
                    sets: sets.map {
                        SetValues(
                            id: $0.id,
                            kind: $0.kind,
                            weight: $0.weight,
                            reps: $0.reps,
                            durationSeconds: $0.durationSeconds,
                            distanceMeters: $0.distanceMeters
                        )
                    }
                )
            }
    }

    // MARK: Header fields

    /// The duration in whole minutes (rounded), the unit the editor's stepper works in.
    public var durationMinutes: Int { Int((Double(durationSeconds) / 60).rounded()) }

    /// Sets the duration in minutes, clamped to at least zero.
    public mutating func setDurationMinutes(_ minutes: Int) {
        durationSeconds = max(0, minutes) * 60
    }

    public var endedAt: Date { startedAt.addingTimeInterval(TimeInterval(durationSeconds)) }

    /// Renames the workout; blank or whitespace-only input is ignored, anything else is trimmed.
    public mutating func rename(to text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        name = trimmed
    }

    // MARK: Set edits

    public mutating func setWeight(_ weight: Double?, for setID: UUID) {
        edit(setID) { $0.weight = weight }
    }

    /// Reps, or seconds when the set's exercise is timed.
    public mutating func setCount(_ value: Int?, for setID: UUID) {
        guard let found = locate(setID) else { return }
        if exercises[found.exercise].isTimed {
            edit(setID) { $0.durationSeconds = value }
        } else {
            edit(setID) { $0.reps = value }
        }
    }

    /// normal → W → D → F → normal.
    public mutating func cycleKind(of setID: UUID) {
        edit(setID) { $0.kind = SetInputFormat.nextKind(after: $0.kind) }
    }

    /// Appends a set that copies the last one's values (a warm-up is followed by a normal set), or an empty normal set.
    public mutating func addSet(to exerciseID: UUID, id: UUID = UUID()) {
        guard let e = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let last = exercises[e].sets.last
        exercises[e].sets.append(
            SetValues(
                id: id,
                kind: last.map { $0.kind == .warmup ? .normal : $0.kind } ?? .normal,
                weight: last?.weight,
                reps: last?.reps,
                durationSeconds: last?.durationSeconds,
                distanceMeters: last?.distanceMeters
            )
        )
    }

    public mutating func deleteSet(_ setID: UUID) {
        guard let found = locate(setID) else { return }
        exercises[found.exercise].sets.remove(at: found.set)
    }

    /// Rewrites the exercise order; ignored unless `order` holds every exercise id exactly once.
    public mutating func reorder(_ order: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        guard order.count == byID.count, Set(order).count == byID.count else { return }
        let ordered = order.compactMap { byID[$0] }
        guard ordered.count == byID.count else { return }
        exercises = ordered
    }

    private func locate(_ setID: UUID) -> (exercise: Int, set: Int)? {
        for (e, row) in exercises.enumerated() {
            if let s = row.sets.firstIndex(where: { $0.id == setID }) { return (e, s) }
        }
        return nil
    }

    private mutating func edit(_ setID: UUID, _ change: (inout SetValues) -> Void) {
        guard let found = locate(setID) else { return }
        change(&exercises[found.exercise].sets[found.set])
    }

    // MARK: Dirty

    /// Whether anything differs from `original`, the draft made when the editor opened.
    public func hasChanges(from original: PastWorkoutDraft) -> Bool { self != original }

    // MARK: Save

    /// Writes the draft to `workout` and saves `context`. On a failed save the context rolls back (so no half-applied
    /// edit is left in the store) and the error is rethrown; the draft itself is untouched and can be saved again.
    @MainActor
    public func save(to workout: Workout, in context: ModelContext, now: Date = .now) throws {
        apply(to: workout, in: context, now: now)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Writes the draft to `workout` without saving. Sets and exercises are matched by id: kept ones are updated in place
    /// (hidden fields survive), new sets are inserted, sets without a value and exercises without a set are deleted. Every
    /// kept set is completed. `finishedAt` becomes `startedAt + duration`, and `completedAt` stamps move with the start.
    @MainActor
    public func apply(to workout: Workout, in context: ModelContext, now: Date = .now) {
        let shift = startedAt.timeIntervalSince(workout.startedAt)
        workout.name = name
        workout.startedAt = startedAt
        workout.finishedAt = endedAt
        workout.updatedAt = now

        let rows = Dictionary(uniqueKeysWithValues: (workout.exercises ?? []).map { ($0.id, $0) })
        let kept = exercises.filter { row in row.sets.contains(where: \.hasValue) }
        let keptIDs = Set(kept.map(\.id))
        for (id, row) in rows where !keptIDs.contains(id) { context.delete(row) }

        // A group left with a single exercise is no superset any more.
        let groupSizes = kept.reduce(into: [Int: Int]()) { counts, row in
            if let group = row.supersetGroup { counts[group, default: 0] += 1 }
        }

        for (position, values) in kept.enumerated() {
            guard let row = rows[values.id] else { continue }
            row.position = position
            row.supersetGroup = values.supersetGroup.flatMap { groupSizes[$0, default: 0] > 1 ? $0 : nil }
            row.updatedAt = now

            let existing = Dictionary(uniqueKeysWithValues: (row.sets ?? []).map { ($0.id, $0) })
            let keptSets = values.sets.filter(\.hasValue)
            let keptSetIDs = Set(keptSets.map(\.id))
            for (id, set) in existing where !keptSetIDs.contains(id) { context.delete(set) }
            for (index, set) in keptSets.enumerated() {
                let model: WorkoutSet
                if let found = existing[set.id] {
                    model = found
                    model.completedAt = model.completedAt.map { $0.addingTimeInterval(shift) } ?? endedAt
                } else {
                    model = WorkoutSet(id: set.id, workoutExercise: row)
                    context.insert(model)
                    model.completedAt = endedAt
                }
                model.position = index
                model.kind = set.kind
                model.weight = set.weight
                model.reps = set.reps
                model.durationSeconds = set.durationSeconds
                model.distanceMeters = set.distanceMeters
                model.completed = true
            }
        }
    }
}
