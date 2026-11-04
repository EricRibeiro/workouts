import Foundation
import Observation
import SwiftData

/// The in-progress workout: start, resume, check sets, Previous autofill, exercise and set edits, finish and discard.
///
/// The in-progress workout is an ordinary `Workout` with `finishedAt == nil` (`data-model.md` section 5), saved on
/// every change, so a new engine on the same store resumes it after relaunch. At most one exists. Every mutation sets
/// `updatedAt` and saves; save errors are thrown and the in-memory change stays (nothing is discarded on error).
/// The rest timer is an engine extension in `RestTimer.swift`; its fields persist on the workout.
@Observable
public final class ActiveWorkoutEngine {
    /// Name of a workout started empty.
    public static let emptyWorkoutName = "Workout"
    /// Sets a freshly added exercise starts with (`workout.md` section 3, "three empty sets").
    public static let defaultSetCount = 3

    /// The in-progress workout, nil when none runs.
    public internal(set) var workout: Workout?

    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let store: ExerciseStore
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let now: () -> Date
    /// Previous entries by exercise id, loaded at start/resume and when exercises are added or replaced.
    @ObservationIgnored var previousCache: [UUID: PreviousEntry] = [:]
    @ObservationIgnored var previousLoaded: Set<UUID> = []

    /// Creates the engine and resumes the in-progress workout, if the store has one (relaunch).
    public init(
        context: ModelContext,
        store: ExerciseStore,
        settings: SettingsStore,
        now: @escaping () -> Date = Date.init
    ) throws {
        self.context = context
        self.store = store
        self.settings = settings
        self.now = now
        try resume()
    }

    /// Reloads the in-progress workout from the store (the newest, if sync ever produced two) and its Previous
    /// values.
    @discardableResult
    public func resume() throws -> Workout? {
        previousCache = [:]
        previousLoaded = []
        let running = try fetchInProgress()
        if let running {
            try loadPrevious(for: Set(sortedExercises(of: running).map(\.exerciseID)))
        }
        workout = running
        if let running {
            var timer = RestTimer(workout: running, now: now)
            if timer.clearIfExpired() {
                timer.write(to: running)
                try commit(running, nil)
            }
        }
        return running
    }

    // MARK: - Start

    /// Starts a workout from `template`: new ids for every exercise and set, sets empty and unchecked (the template's
    /// values stay readable through ``plan(for:)``), the template kept on `Workout.template`.
    /// - Throws: ``ActiveWorkoutError/workoutInProgress(name:)`` when one is running.
    @discardableResult
    public func start(from template: Template) throws -> Workout {
        try refuseIfRunning()
        return try begin(name: template.name.isEmpty ? Self.emptyWorkoutName : template.name) { workout in
            workout.template = template
            let rows = (template.exercises ?? []).sorted { $0.position < $1.position }
            for (position, source) in rows.enumerated() {
                let row = self.insertRow(
                    into: workout,
                    exerciseID: source.exerciseID,
                    name: source.exerciseName.isEmpty
                        ? (self.store.exercise(id: source.exerciseID)?.name ?? "") : source.exerciseName,
                    position: position,
                    unit: source.unit,
                    barType: source.barType,
                    barWeight: source.barWeight,
                    restSeconds: source.restSeconds ?? self.settings.defaultRestSeconds
                )
                row.supersetGroup = source.supersetGroup
                row.note = source.note
                let sets = (source.sets ?? []).sorted { $0.position < $1.position }
                for (index, plan) in sets.enumerated() {
                    self.insertSet(into: row, position: index, kind: plan.kind)
                }
            }
        }
    }

    /// Starts a workout named "Workout" with no exercises.
    /// - Throws: ``ActiveWorkoutError/workoutInProgress(name:)`` when one is running.
    @discardableResult
    public func startEmpty() throws -> Workout {
        try refuseIfRunning()
        return try begin(name: Self.emptyWorkoutName) { _ in }
    }

    // MARK: - Sets

    /// Checks `set`: first fills empty weight, reps and duration from Previous, else from the plan, then marks it
    /// completed (`completedAt = now`). Already-checked sets are left alone.
    /// - Throws: ``ActiveWorkoutError/emptySet`` when nothing to record remains even after filling; nothing changes.
    public func check(_ set: WorkoutSet) throws {
        let (workout, row) = try owner(of: set)
        guard !set.completed else { return }
        let filled = filledValues(of: set, in: row)
        guard hasValues(weight: filled.weight, reps: filled.reps, duration: filled.duration, row: row) else {
            throw ActiveWorkoutError.emptySet
        }
        set.weight = filled.weight
        set.reps = filled.reps
        set.durationSeconds = filled.duration
        set.completed = true
        set.completedAt = now()
        try startRest(afterChecking: set, in: row, workout: workout)
        try commit(workout, row)
    }

    /// Unchecks `set`: back to unchecked with its values kept.
    public func uncheck(_ set: WorkoutSet) throws {
        let (workout, row) = try owner(of: set)
        guard set.completed else { return }
        set.completed = false
        set.completedAt = nil
        cancelRest(ownedBy: [set.id], workout: workout)
        try commit(workout, row)
    }

    /// Sets the typed values of `set` (nil clears a field). Weight is clamped to >= 0 with at most 2 decimals; reps and
    /// duration to >= 0.
    public func setValues(_ set: WorkoutSet, weight: Double?, reps: Int?, durationSeconds: Int?) throws {
        let (workout, row) = try owner(of: set)
        set.weight = weight.map { max(0, ($0 * 100).rounded() / 100) }
        set.reps = reps.map { max(0, $0) }
        set.durationSeconds = durationSeconds.map { max(0, $0) }
        try commit(workout, row)
    }

    /// Sets the kind of `set` (W, D, F or normal).
    public func setKind(_ set: WorkoutSet, to kind: SetKind) throws {
        let (workout, row) = try owner(of: set)
        set.kind = kind
        try commit(workout, row)
    }

    /// Appends a set to `row` that copies the last set's values, unchecked; a warm-up copy becomes a normal set.
    /// An exercise with no sets gets an empty one.
    @discardableResult
    public func addSet(to row: WorkoutExercise) throws -> WorkoutSet {
        let workout = try owned(row)
        let last = sortedSets(of: row).last
        let set = insertSet(
            into: row,
            position: (last?.position ?? -1) + 1,
            kind: last.map { $0.kind == .warmup ? .normal : $0.kind } ?? .normal
        )
        set.weight = last?.weight
        set.reps = last?.reps
        set.durationSeconds = last?.durationSeconds
        set.distanceMeters = last?.distanceMeters
        try commit(workout, row)
        return set
    }

    /// Deletes `set` and renumbers the rest of the exercise's sets.
    public func removeSet(_ set: WorkoutSet) throws {
        let (workout, row) = try owner(of: set)
        cancelRest(ownedBy: [set.id], workout: workout)
        context.delete(set)
        for (position, remaining) in sortedSets(of: row).filter({ $0 !== set }).enumerated() {
            remaining.position = position
        }
        try commit(workout, row)
    }

    /// The "Previous" cell of `set`: the same set index among the completed sets of the exercise's most recent
    /// finished workout that has any, in the row's unit (converted and rounded to 0.5 when the units differ).
    /// Values are loaded at start, resume and when an exercise is added or replaced.
    public func previous(for set: WorkoutSet) -> PreviousSet? {
        guard let row = set.workoutExercise, let entry = previousCache[row.exerciseID],
            let index = sortedSets(of: row).firstIndex(where: { $0 === set }), entry.sets.indices.contains(index)
        else { return nil }
        let source = entry.sets[index]
        return PreviousSet(
            kind: source.kind,
            weight: source.weight.map { convertedWeight($0, from: entry.unit, to: row.unit) },
            reps: source.reps,
            durationSeconds: source.durationSeconds
        )
    }

    /// Copies the set's Previous weight, reps and duration into `set` (the Previous key/cell); fields Previous lacks
    /// are left alone. Returns false when there is no Previous.
    @discardableResult
    public func applyPrevious(to set: WorkoutSet) throws -> Bool {
        let (workout, row) = try owner(of: set)
        guard let previous = previous(for: set) else { return false }
        if let weight = previous.weight { set.weight = weight }
        if let reps = previous.reps { set.reps = reps }
        if let duration = previous.durationSeconds { set.durationSeconds = duration }
        try commit(workout, row)
        return true
    }

    /// The template's plan for `set` (same exercise id, same set index), or nil without a template, for exercises
    /// added later, or for sets past the template's.
    public func plan(for set: WorkoutSet) -> SetPlan? {
        guard let row = set.workoutExercise, let template = row.workout?.template,
            let index = sortedSets(of: row).firstIndex(where: { $0 === set })
        else { return nil }
        let source = (template.exercises ?? []).sorted { $0.position < $1.position }
            .first { $0.exerciseID == row.exerciseID }
        guard let planned = source.map({ ($0.sets ?? []).sorted { $0.position < $1.position } }),
            planned.indices.contains(index)
        else { return nil }
        let value = planned[index]
        return SetPlan(weight: value.weight, reps: value.reps, durationSeconds: value.durationSeconds)
    }

    // MARK: - Exercises

    /// Appends `info` with its defaults: a custom exercise's own unit, bar and rest if set, else Settings `defaultUnit`,
    /// an Olympic bar for barbells (none otherwise) and `defaultRestSeconds`; three empty sets.
    @discardableResult
    public func addExercise(_ info: ExerciseInfo) throws -> WorkoutExercise {
        try addExercises([info])[0]
    }

    /// Appends several exercises at once (the picker's multi-select), in order.
    @discardableResult
    public func addExercises(_ infos: [ExerciseInfo]) throws -> [WorkoutExercise] {
        let workout = try activeWorkout()
        try loadPrevious(for: Set(infos.map(\.id)))
        var position = sortedExercises(of: workout).count
        var added: [WorkoutExercise] = []
        for info in infos {
            let row = insertRow(
                into: workout,
                exerciseID: info.id,
                name: info.name,
                position: position,
                unit: info.unit ?? settings.defaultUnit,
                barType: info.barType ?? (info.weightType == .barbell ? .olympic : .none),
                barWeight: info.barWeight,
                restSeconds: info.restSeconds ?? settings.defaultRestSeconds
            )
            for index in 0..<Self.defaultSetCount { insertSet(into: row, position: index, kind: .normal) }
            added.append(row)
            position += 1
        }
        try commit(workout, nil)
        return added
    }

    /// Replaces the exercise of `row` with `info`; sets, note, rest, unit and bar stay (the set values are not
    /// converted).
    public func replaceExercise(_ row: WorkoutExercise, with info: ExerciseInfo) throws {
        let workout = try owned(row)
        try loadPrevious(for: [info.id])
        row.exerciseID = info.id
        row.exerciseName = info.name
        try commit(workout, row)
    }

    /// Removes `row` with its sets, renumbers positions and dissolves a superset left with one member.
    public func removeExercise(_ row: WorkoutExercise) throws {
        let workout = try owned(row)
        cancelRest(ownedBy: Set(sortedSets(of: row).map(\.id)), workout: workout)
        context.delete(row)
        let remaining = sortedExercises(of: workout).filter { $0 !== row }
        renumber(remaining)
        try commit(workout, nil)
    }

    /// Rewrites exercise positions from `order`, which must contain each of the workout's exercises exactly once.
    public func reorderExercises(_ order: [WorkoutExercise]) throws {
        let workout = try activeWorkout()
        let current = sortedExercises(of: workout)
        guard order.count == current.count,
            Set(order.map(ObjectIdentifier.init)) == Set(current.map(ObjectIdentifier.init))
        else { throw ActiveWorkoutError.invalidOrder }
        for (position, row) in order.enumerated() {
            row.position = position
            row.updatedAt = now()
        }
        try commit(workout, nil)
    }

    /// Renames the workout.
    public func rename(to name: String) throws {
        let workout = try activeWorkout()
        workout.name = name
        try commit(workout, nil)
    }

    // MARK: - Finish and discard

    /// What the Finish flow needs right now: which dialog to show and the numbers of the summary, computed as if the
    /// unchecked sets were dropped (the default outcome); PRs run against the finished workouts.
    public func finishSummary() throws -> FinishSummary {
        let workout = try activeWorkout()
        let rows = sortedExercises(of: workout).map { ($0, sortedSets(of: $0)) }
        let kept = rows.map { row, sets in (row, sets.filter(\.completed)) }.filter { !$0.1.isEmpty }
        let unchecked = rows.flatMap { row, sets in sets.filter { !$0.completed }.map { (row, $0) } }
        let withValues = unchecked.filter { hasValues($0.1, in: $0.0) }.count
        return try makeSummary(
            workout: workout,
            kept: kept,
            end: now(),
            workoutNumber: try finishedCount(excluding: workout) + 1,
            uncheckedWithValues: withValues,
            uncheckedWithoutValues: unchecked.count - withValues
        )
    }

    /// Finishes the workout: `finishedAt` is set (clamped to >= `startedAt`), unchecked sets are checked or dropped per
    /// `unfinished`, unchecked sets without values and exercises with no checked set are dropped, positions are
    /// renumbered. A running rest is cleared.Returns the summary for the finish sheet; the engine then has
    /// no workout.
    /// - Throws: ``ActiveWorkoutError/nothingLogged`` when no set is checked; nothing changes.
    @discardableResult
    public func finish(unfinished: UnfinishedSets) throws -> FinishSummary {
        let workout = try activeWorkout()
        let rows = sortedExercises(of: workout)
        guard rows.contains(where: { sortedSets(of: $0).contains(where: \.completed) }) else {
            throw ActiveWorkoutError.nothingLogged
        }
        let end = max(now(), workout.startedAt)
        var kept: [(WorkoutExercise, [WorkoutSet])] = []
        var keptRows: [WorkoutExercise] = []
        for row in rows {
            var survivors: [WorkoutSet] = []
            for set in sortedSets(of: row) {
                if !set.completed && unfinished == .complete && hasValues(set, in: row) {
                    set.completed = true
                    set.completedAt = end
                }
                if set.completed { survivors.append(set) } else { context.delete(set) }
            }
            if survivors.isEmpty {
                context.delete(row)
            } else {
                for (position, set) in survivors.enumerated() { set.position = position }
                kept.append((row, survivors))
                keptRows.append(row)
            }
        }
        renumber(keptRows)
        workout.finishedAt = end
        RestTimer().write(to: workout)
        try commit(workout, nil)
        let summary = try makeSummary(
            workout: workout,
            kept: kept,
            end: end,
            workoutNumber: try finishedCount(excluding: workout) + 1,
            uncheckedWithValues: 0,
            uncheckedWithoutValues: 0
        )
        self.workout = nil
        previousCache = [:]
        previousLoaded = []
        return summary
    }

    /// Deletes the workout with everything in it. The caller confirms first ("Discard workout?").
    public func discard() throws {
        let workout = try activeWorkout()
        // Cleared first so nothing observing the engine can read the model while it is being deleted.
        self.workout = nil
        context.delete(workout)
        try context.save()
        previousCache = [:]
        previousLoaded = []
    }
}
