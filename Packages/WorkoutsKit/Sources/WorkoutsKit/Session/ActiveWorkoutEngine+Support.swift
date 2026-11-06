import Foundation
import SwiftData

/// An exercise's most recent finished performance: its completed sets in order, in that entry's unit.
struct PreviousEntry {
    var unit: WeightUnit
    var sets: [PreviousSet]
}

/// The typed values of one set that are in the model but not yet saved (see ``ActiveWorkoutEngine/setValues(_:weight:reps:durationSeconds:)``).
struct PendingValues {
    var weight: Double?
    var reps: Int?
    var durationSeconds: Int?
}

// MARK: - Lookup and persistence

extension ActiveWorkoutEngine {
    func fetchInProgress() throws -> Workout? {
        try context.fetch(Workout.inProgress).first
    }

    func refuseIfRunning() throws {
        if let running = try fetchInProgress() {
            workout = running
            throw ActiveWorkoutError.workoutInProgress(name: running.name)
        }
    }

    /// ``workout`` only while it is safe to read: not deleted and still in a context. Reading a persisted property of a
    /// deleted model traps in SwiftData, so every read-only derivation (rest timer, activity state, notification plan)
    /// goes through this and reports "nothing running" instead.
    var liveWorkout: Workout? {
        guard let workout, !workout.isDeleted, workout.modelContext != nil else { return nil }
        return workout
    }

    func activeWorkout() throws -> Workout {
        guard let workout else { throw ActiveWorkoutError.noActiveWorkout }
        return workout
    }

    func owned(_ row: WorkoutExercise) throws -> Workout {
        let workout = try activeWorkout()
        guard row.workout === workout else { throw ActiveWorkoutError.notInActiveWorkout }
        return workout
    }

    func owner(of set: WorkoutSet) throws -> (Workout, WorkoutExercise) {
        guard let row = set.workoutExercise else { throw ActiveWorkoutError.notInActiveWorkout }
        return (try owned(row), row)
    }

    /// Stamps `updatedAt` on the workout (and `row`) and saves.
    func commit(_ workout: Workout, _ row: WorkoutExercise?) throws {
        let stamp = now()
        workout.updatedAt = stamp
        row?.updatedAt = stamp
        try save()
    }

    /// Saves through the test seam ``saveHook``.
    func save() throws {
        try saveHook?()
        try context.save()
        pendingEdits.removeAll()
    }

    /// `context.rollback()` that keeps the typed values waiting for a save: a failed structural edit (add or remove a set,
    /// finish, discard) must undo only itself, as it did when every keystroke was saved. Values of sets that no longer
    /// exist after the rollback are dropped.
    func rollbackKeepingEdits(in workout: Workout) {
        let pending = pendingEdits
        context.rollback()
        pendingEdits = [:]
        for set in (workout.exercises ?? []).flatMap({ $0.sets ?? [] }) {
            guard let values = pending[set.id] else { continue }
            set.weight = values.weight
            set.reps = values.reps
            set.durationSeconds = values.durationSeconds
            pendingEdits[set.id] = values
        }
        if !pendingEdits.isEmpty { workout.updatedAt = now() }
    }

    /// ``commit(_:_:)`` for mutations that insert, delete or renumber several models: when the save fails the whole
    /// in-memory change is rolled back, so the context never keeps deleted rows or half-applied positions that a
    /// retry or the next read would walk.
    func commitRollingBack(_ workout: Workout, _ row: WorkoutExercise?) throws {
        do {
            try commit(workout, row)
        } catch {
            rollbackKeepingEdits(in: workout)
            throw error
        }
    }

    /// Inserts a new workout, lets `build` fill it, loads Previous for its exercises and saves. On failure the new
    /// workout is removed from the context again.
    func begin(name: String, build: (Workout) -> Void) throws -> Workout {
        let stamp = now()
        let workout = Workout(name: name, startedAt: stamp, createdAt: stamp, updatedAt: stamp)
        context.insert(workout)
        previousCache = [:]
        previousLoaded = []
        do {
            build(workout)
            try loadPrevious(for: Set(sortedExercises(of: workout).map(\.exerciseID)))
            try save()
        } catch {
            context.rollback()
            throw error
        }
        self.workout = workout
        return workout
    }

    func sortedExercises(of workout: Workout) -> [WorkoutExercise] {
        (workout.exercises ?? []).sorted { $0.position < $1.position }
    }

    func sortedSets(of row: WorkoutExercise) -> [WorkoutSet] {
        (row.sets ?? []).sorted { $0.position < $1.position }
    }

    func insertRow(
        into workout: Workout,
        exerciseID: UUID,
        name: String,
        position: Int,
        unit: WeightUnit,
        barType: BarType,
        barWeight: Double?,
        restSeconds: Int?
    ) -> WorkoutExercise {
        let row = WorkoutExercise(
            exerciseID: exerciseID,
            exerciseName: name,
            position: position,
            restSeconds: restSeconds,
            unit: unit,
            barType: barType,
            barWeight: barWeight,
            updatedAt: now()
        )
        context.insert(row)
        row.workout = workout
        return row
    }

    @discardableResult
    func insertSet(into row: WorkoutExercise, position: Int, kind: SetKind) -> WorkoutSet {
        let set = WorkoutSet(position: position, kind: kind)
        context.insert(set)
        set.workoutExercise = row
        return set
    }

    /// Rewrites positions 0... in the given order and dissolves supersets left with fewer than two members.
    func renumber(_ rows: [WorkoutExercise]) {
        var members: [Int: Int] = [:]
        for row in rows { if let group = row.supersetGroup { members[group, default: 0] += 1 } }
        for (position, row) in rows.enumerated() {
            row.position = position
            if let group = row.supersetGroup, members[group, default: 0] < 2 { row.supersetGroup = nil }
            row.updatedAt = now()
        }
    }
}

// MARK: - Values

extension ActiveWorkoutEngine {
    /// Cross-unit Previous values convert and round to 0.5; same-unit values are untouched.
    func convertedWeight(_ weight: Double, from: WeightUnit, to: WeightUnit) -> Double {
        from == to ? weight : round05(convert(weight, from: from, to: to))
    }

    /// `filled()`: empty weight, reps and duration take Previous, else the plan.
    func filledValues(of set: WorkoutSet, in row: WorkoutExercise) -> (weight: Double?, reps: Int?, duration: Int?) {
        let previous = previous(for: set)
        let plan = plan(for: set)
        return (
            set.weight ?? previous?.weight ?? plan?.weight,
            set.reps ?? previous?.reps ?? plan?.reps,
            set.durationSeconds ?? previous?.durationSeconds ?? plan?.durationSeconds
        )
    }

    /// Something to record: reps or a duration above 0, or (strength types only) a weight above 0. For the rep types
    /// and assisted the weight is only an addition or an assistance, so on its own it is not a set.
    func hasValues(weight: Double?, reps: Int?, duration: Int?, row: WorkoutExercise) -> Bool {
        if (reps ?? 0) > 0 || (duration ?? 0) > 0 { return true }
        let category = store.exercise(id: row.exerciseID)?.weightType.category ?? .strength
        return category == .strength && (weight ?? 0) > 0
    }

    func hasValues(_ set: WorkoutSet, in row: WorkoutExercise) -> Bool {
        hasValues(weight: set.weight, reps: set.reps, duration: set.durationSeconds, row: row)
    }
}

// MARK: - Previous

extension ActiveWorkoutEngine {
    /// Loads Previous for the ids not loaded yet: per exercise the most recent finished workout (by `startedAt`
    /// descending, then position) with at least one completed set of it.
    func loadPrevious(for ids: Set<UUID>) throws {
        var pending = ids.subtracting(previousLoaded)
        guard !pending.isEmpty else { return }
        let finished = try context.fetch(
            FetchDescriptor<Workout>(
                predicate: Workout.finishedPredicate,
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        )
        for past in finished where !pending.isEmpty {
            let rows = sortedExercises(of: past)
            for id in pending {
                let sameExercise = rows.filter { $0.exerciseID == id }
                let entries = sameExercise.map { row in
                    PreviousEntry(
                        unit: row.unit,
                        sets: sortedSets(of: row).filter(\.completed).map {
                            PreviousSet(
                                kind: $0.kind,
                                weight: $0.weight,
                                reps: $0.reps,
                                durationSeconds: $0.durationSeconds
                            )
                        }
                    )
                }
                guard entries.contains(where: { !$0.sets.isEmpty }) else { continue }
                previousCache[id] = entries
                pending.remove(id)
            }
        }
        previousLoaded.formUnion(ids)
    }
}

// MARK: - Summary

extension ActiveWorkoutEngine {
    func finishedCount(excluding workout: Workout) throws -> Int {
        let id = workout.id
        return try context.fetchCount(
            FetchDescriptor<Workout>(predicate: Workout.finishedPredicate(excluding: id))
        )
    }

    /// One session per past finished workout and exercise, by exercise id.
    private func historySessions(for ids: Set<UUID>, excluding workout: Workout) throws -> [UUID: [Session]] {
        let id = workout.id
        let finished = try context.fetch(
            FetchDescriptor<Workout>(predicate: Workout.finishedPredicate(excluding: id))
        )
        var sessions: [UUID: [Session]] = [:]
        for past in finished {
            for row in sortedExercises(of: past) where ids.contains(row.exerciseID) {
                sessions[row.exerciseID, default: []].append(
                    Session(
                        workoutID: past.id,
                        time: past.startedAt,
                        exerciseID: row.exerciseID,
                        weightType: store.exercise(id: row.exerciseID)?.weightType ?? .weighted,
                        sets: loggedSets(of: row, only: sortedSets(of: row).filter(\.completed))
                    )
                )
            }
        }
        return sessions
    }

    private func loggedSets(of row: WorkoutExercise, only sets: [WorkoutSet]) -> [LoggedSet] {
        sets.map {
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
    }

    /// Unchecked sets with and without something to record, over all of the workout's rows.
    func uncheckedCounts(in rows: [(WorkoutExercise, [WorkoutSet])]) -> (withValues: Int, withoutValues: Int) {
        let unchecked = rows.flatMap { row, sets in sets.filter { !$0.completed }.map { (row, $0) } }
        let withValues = unchecked.filter { hasValues($0.1, in: $0.0) }.count
        return (withValues, unchecked.count - withValues)
    }

    /// The one rule for which Finish dialog applies.
    static func dialog(anyChecked: Bool, uncheckedWithValues: Int, uncheckedWithoutValues: Int) -> FinishDialog {
        guard anyChecked else { return .nothingLogged }
        if uncheckedWithValues > 0 { return .unfinishedWithValues(count: uncheckedWithValues) }
        if uncheckedWithoutValues > 0 { return .unfinishedWithoutValues(count: uncheckedWithoutValues) }
        return .none
    }

    /// The summary of `kept` (rows with the checked sets that are or will be saved).
    func makeSummary(
        workout: Workout,
        kept: [(WorkoutExercise, [WorkoutSet])],
        end: Date,
        workoutNumber: Int,
        uncheckedWithValues: Int,
        uncheckedWithoutValues: Int
    ) throws -> FinishSummary {
        let displayUnit = settings.defaultUnit
        let options = RecordsOptions(formula: settings.e1rmFormula, displayUnit: displayUnit)

        // One session per exercise id: rows of the same exercise merge.
        var order: [UUID] = []
        var names: [UUID: String] = [:]
        var sets: [UUID: [LoggedSet]] = [:]
        for (row, checked) in kept {
            if sets[row.exerciseID] == nil {
                order.append(row.exerciseID)
                names[row.exerciseID] = row.exerciseName
            }
            sets[row.exerciseID, default: []].append(contentsOf: loggedSets(of: row, only: checked))
        }

        let history = try historySessions(for: Set(order), excluding: workout)
        var prs: [ExercisePRs] = []
        var volumeKg = 0.0
        for id in order {
            let weightType = store.exercise(id: id)?.weightType ?? .weighted
            let logged = sets[id] ?? []
            if weightType.category != .assisted {
                volumeKg += countedSets(logged).reduce(0) { $0 + $1.weightKg * Double($1.reps) }
            }
            let session = Session(
                workoutID: workout.id,
                time: workout.startedAt,
                exerciseID: id,
                weightType: weightType,
                sets: logged
            )
            let records = prsInSession(
                history: history[id] ?? [],
                session: session,
                weightType: weightType,
                options: options
            )
            if !records.isEmpty {
                prs.append(ExercisePRs(exerciseID: id, exerciseName: names[id] ?? "", records: records))
            }
        }

        let setCount = kept.reduce(0) { $0 + $1.1.count }
        let dialog = Self.dialog(
            anyChecked: setCount > 0,
            uncheckedWithValues: uncheckedWithValues,
            uncheckedWithoutValues: uncheckedWithoutValues
        )
        return FinishSummary(
            duration: max(0, end.timeIntervalSince(workout.startedAt)),
            setCount: setCount,
            exerciseCount: kept.count,
            volume: round05(convert(volumeKg, from: .kg, to: displayUnit)),
            volumeUnit: displayUnit,
            prs: prs,
            prCount: prs.reduce(0) { $0 + $1.records.count },
            workoutNumber: workoutNumber,
            uncheckedWithValues: uncheckedWithValues,
            uncheckedWithoutValues: uncheckedWithoutValues,
            dialog: dialog,
            workoutID: workout.id
        )
    }
}
