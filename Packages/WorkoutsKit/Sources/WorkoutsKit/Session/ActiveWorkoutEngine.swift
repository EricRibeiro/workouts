import Foundation
import Observation
import SwiftData
import os

/// The in-progress workout: start, resume, check sets, Previous autofill, exercise and set edits, finish and discard.
///
/// The in-progress workout is an ordinary `Workout` with `finishedAt == nil` (`data-model.md` section 5), saved on
/// every change, so a new engine on the same store resumes it after relaunch. At most one exists. Every mutation sets
/// `updatedAt` and saves; save errors are thrown. Value edits keep their in-memory change on error; mutations that
/// insert, delete or renumber models, ``finish(unfinished:)`` and ``discard()`` roll the context back instead.
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
    /// Whether an exercise (by library or custom id) records a duration from its first set, e.g. an isometric hold.
    /// A lookup, not a one-time insert, so it still holds for the persisted workout after a relaunch.
    @ObservationIgnored let timedByDefault: (UUID) -> Bool
    /// Previous entries by exercise id, loaded at start/resume and when exercises are added or replaced.
    /// Per exercise id, one entry per row of that exercise in the chosen past workout, by position (an entry may have no sets).
    @ObservationIgnored var previousCache: [UUID: [PreviousEntry]] = [:]
    @ObservationIgnored var previousLoaded: Set<UUID> = []
    /// Test seam: runs before every save and may throw to simulate a failed save. Always nil in the app.
    @ObservationIgnored var saveHook: (() throws -> Void)?
    /// Typed values (``setValues(_:weight:reps:durationSeconds:)``) that are in the models but not yet saved, by set id.
    /// Cleared by every successful save; re-applied after a rollback so a failed structural edit cannot eat them.
    @ObservationIgnored var pendingEdits: [UUID: PendingValues] = [:]
    /// Workout exercises (by id) already decided to be timed; see ``isTimed(_:)``.
    @ObservationIgnored var timedExercises: Set<UUID> = []
    /// Per-set results of ``previous(for:)`` and ``plan(for:)`` and per-row "Previous or plan has a duration" answers,
    /// filled on first read so a table build does not redo the sorts for every set. They read only the workout's
    /// structure (exercise and set order, kinds, ids, unit), ``previousCache`` and the template, never typed values or
    /// checks, so only structural edits clear them (``invalidateLookups()``); the plan entries also carry the
    /// template's `updatedAt`, which a template edit stamps.
    @ObservationIgnored var previousLookups: [UUID: LookupResult<PreviousSet>] = [:]
    @ObservationIgnored var planLookups: [UUID: PlanLookup] = [:]
    @ObservationIgnored var derivedTimedLookups: [UUID: Bool] = [:]
    /// Test seam: called each time a Previous or plan lookup is computed instead of served from the cache.
    @ObservationIgnored var lookupProbe: ((LookupKind) -> Void)?

    /// Creates the engine and resumes the in-progress workout, if the store has one (relaunch).
    public init(
        context: ModelContext,
        store: ExerciseStore,
        settings: SettingsStore,
        now: @escaping () -> Date = Date.init,
        timedByDefault: @escaping (UUID) -> Bool = { _ in false }
    ) throws {
        self.context = context
        self.timedByDefault = timedByDefault
        self.store = store
        self.settings = settings
        self.now = now
        try resume()
    }

    /// Reloads the in-progress workout from the store and its Previous values. When sync produced more than one
    /// in-progress workout the newest-started live one stays; older ones untouched for 6 h are finished at their last
    /// completed set, or deleted when nothing was logged (``InProgressResolution``, the C-01 end-time rule), and a
    /// recently updated older one is left running.
    @discardableResult
    public func resume() throws -> Workout? {
        settleExtraInProgress()
        resetPrevious()
        let running = try fetchInProgress()
        if let running {
            try loadPrevious(for: Set(sortedExercises(of: running).map(\.exerciseID)))
        }
        workout = running
        if let running {
            var timer = RestTimer(workout: running, now: now)
            if timer.clearIfExpired() {
                timer.write(to: running)
                // Best effort: clearing a stale timer must never fail the launch (`init` calls this). The cleared
                // timer stays in memory and is saved with the next edit.
                do {
                    try commit(running, nil)
                } catch {
                    KitLog.engine.error(
                        "Could not save the cleared rest timer: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
        return running
    }

    /// Rebuilds the Previous values from the store, as ``resume()`` does, without touching the running workout. The
    /// app calls it when CloudKit merged remote changes in, so a workout finished on another device shows up as Previous.
    public func reloadPrevious() throws {
        resetPrevious()
        if let running = liveWorkout {
            try loadPrevious(for: Set(sortedExercises(of: running).map(\.exerciseID)))
        }
    }

    /// What the app does when CloudKit merged remote changes in (P-01): rebuilds Previous, and re-settles the running
    /// workout through ``resume()`` when this device's `workout` is gone (deleted or detached by a merge, finished on
    /// another device) or nil (a workout may have been started elsewhere). A workout still running here is kept, so
    /// the one being logged is not swapped under the person's hands.
    public func reloadAfterRemoteChange() throws {
        // The store is the truth: a model another context deleted or finished can still look alive (and trap when read)
        // until the context refreshes it, so ask the store whether the workout is still in progress, by identity only.
        if let running = liveWorkout, try inProgressIdentifiers().contains(running.persistentModelID) {
            try reloadPrevious()
        } else {
            try resume()
        }
    }

    private func inProgressIdentifiers() throws -> Set<PersistentIdentifier> {
        Set(
            try context.fetch(FetchDescriptor<Workout>(predicate: Workout.inProgressPredicate)).map(\.persistentModelID)
        )
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
                    restSeconds: source.restSeconds
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

    /// Whether ``check(_:)`` would succeed on `set`: something to record remains once empty fields are filled from Previous or
    /// the plan. Always `false` for a set outside the active workout; already-checked sets report `true`.
    public func canCheck(_ set: WorkoutSet) -> Bool {
        guard let row = set.workoutExercise else { return false }
        if set.completed { return true }
        let filled = filledValues(of: set, in: row)
        return hasValues(weight: filled.weight, reps: filled.reps, duration: filled.duration, row: row)
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
    ///
    /// **Does not save.** The set field calls this on every keystroke; the values go into the models at once (the Live
    /// Activity, the rest notification and the table all observe the models, not the store), and are written by the next
    /// commit point: ``commitEdits()`` (focus leaves the field, the app goes inactive) or any other engine mutation, whose
    /// save takes them along (check, Previous, add or remove a set, finish).
    public func setValues(_ set: WorkoutSet, weight: Double?, reps: Int?, durationSeconds: Int?) throws {
        let (workout, row) = try owner(of: set)
        set.weight = weight.map { max(0, ($0 * 100).rounded() / 100) }
        set.reps = reps.map { max(0, $0) }
        set.durationSeconds = durationSeconds.map { max(0, $0) }
        let stamp = now()
        workout.updatedAt = stamp
        row.updatedAt = stamp
        pendingEdits[set.id] = PendingValues(
            weight: set.weight,
            reps: set.reps,
            durationSeconds: set.durationSeconds
        )
    }

    /// Whether typed values are waiting for a save.
    public var hasUncommittedEdits: Bool { !pendingEdits.isEmpty }

    /// Saves the values typed since the last save (a no-op when there are none). Called when focus leaves a set field and
    /// when the app goes inactive. On failure the values stay in the models and pending, so the next commit point retries;
    /// the error is the caller's to surface.
    public func commitEdits() throws {
        guard hasUncommittedEdits else { return }
        try save()
    }

    /// Sets the kind of `set` (W, D, F or normal).
    public func setKind(_ set: WorkoutSet, to kind: SetKind) throws {
        let (workout, row) = try owner(of: set)
        set.kind = kind
        invalidateLookups()
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
        try commitRollingBack(workout, row)
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
        try commitRollingBack(workout, row)
    }

    /// The "Previous" cell of `set`: the same set among the completed sets of the exercise's most recent
    /// finished workout that has any, in the row's unit (converted and rounded to 0.5 when the units differ).
    /// Like ``plan(for:)``, the n-th workout row of an exercise takes the n-th row of that exercise in the past workout
    /// (by position), so Squat 100x5 then Squat 60x12 last time shows 100x5 and 60x12. A row with no n-th counterpart
    /// (or whose counterpart has no completed sets) falls back to the past workout's first row with completed sets, so
    /// an extra row added this time still gets a hint.
    /// Values are loaded at start, resume and when an exercise is added or replaced.
    public func previous(for set: WorkoutSet) -> PreviousSet? {
        if let cached = previousLookups[set.id] { return cached.value }
        lookupProbe?(.previous)
        let value = computePrevious(for: set)
        previousLookups[set.id] = LookupResult(value: value)
        return value
    }

    private func computePrevious(for set: WorkoutSet) -> PreviousSet? {
        guard let row = set.workoutExercise, let entries = previousCache[row.exerciseID] else { return nil }
        var nth = 0
        if let workout = row.workout {
            let rows = (workout.exercises ?? []).sorted { $0.position < $1.position }
                .filter { $0.exerciseID == row.exerciseID }
            nth = rows.firstIndex(where: { $0 === row }) ?? 0
        }
        let candidate = entries.indices.contains(nth) && !entries[nth].sets.isEmpty ? entries[nth] : nil
        guard let entry = candidate ?? entries.first(where: { !$0.sets.isEmpty }),
            let index = Self.indexByKind(of: set, in: sortedSets(of: row), among: entry.sets.map(\.kind))
        else { return nil }
        let source = entry.sets[index]
        return PreviousSet(
            kind: source.kind,
            weight: source.weight.map { convertedWeight($0, from: entry.unit, to: row.unit) },
            reps: source.reps,
            durationSeconds: source.durationSeconds
        )
    }

    /// The index in `kinds` (a plan's or Previous's set kinds, in order) that `set` takes: warm-up sets take the n-th
    /// warm-up, every other set the n-th non-warm-up, so adding or dropping warm-ups never shifts the working sets'
    /// values. Nil when there is no n-th.
    static func indexByKind(of set: WorkoutSet, in sets: [WorkoutSet], among kinds: [SetKind]) -> Int? {
        let isWarmup = set.kind == .warmup
        guard let position = sets.firstIndex(where: { $0 === set }) else { return nil }
        let nth = sets[..<position].filter { ($0.kind == .warmup) == isWarmup }.count
        let matches = kinds.indices.filter { (kinds[$0] == .warmup) == isWarmup }
        return matches.indices.contains(nth) ? matches[nth] : nil
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

    /// The template's plan for `set`, or nil without a template, for exercises added later, or for sets past the
    /// template's. The n-th workout row of an exercise takes the n-th template row of that exercise (by position), so
    /// a template with the same exercise twice plans each row separately. The weight is in the row's current unit
    /// (converted and rounded to 0.5 from the template row's unit when they differ, as for Previous).
    public func plan(for set: WorkoutSet) -> SetPlan? {
        let stamp = set.workoutExercise?.workout?.template?.updatedAt
        if let cached = planLookups[set.id], cached.templateStamp == stamp { return cached.result.value }
        lookupProbe?(.plan)
        let value = computePlan(for: set)
        planLookups[set.id] = PlanLookup(templateStamp: stamp, result: LookupResult(value: value))
        return value
    }

    private func computePlan(for set: WorkoutSet) -> SetPlan? {
        guard let row = set.workoutExercise, let workout = row.workout, let template = workout.template
        else { return nil }
        let sameExercise: (WorkoutExercise) -> Bool = { $0.exerciseID == row.exerciseID }
        let workoutRows = (workout.exercises ?? []).sorted { $0.position < $1.position }.filter(sameExercise)
        guard let nth = workoutRows.firstIndex(where: { $0 === row }) else { return nil }
        let sources = (template.exercises ?? []).sorted { $0.position < $1.position }
            .filter { $0.exerciseID == row.exerciseID }
        guard sources.indices.contains(nth) else { return nil }
        let source = sources[nth]
        let planned = (source.sets ?? []).sorted { $0.position < $1.position }
        guard let index = Self.indexByKind(of: set, in: sortedSets(of: row), among: planned.map(\.kind)) else {
            return nil
        }
        let value = planned[index]
        return SetPlan(
            weight: value.weight.map { convertedWeight($0, from: source.unit, to: row.unit) },
            reps: value.reps,
            durationSeconds: value.durationSeconds
        )
    }

    /// Whether `row` records a duration instead of reps: any of its sets has one, or the Previous or the template plan
    /// behind a set has one (a plank planned at 60 s with no history is already timed), or the exercise is timed by default.
    ///
    /// Once true it stays true for the life of the engine, like `TemplateDraft.isTimed` is fixed at row creation:
    /// clearing the only set that has a duration must not turn the column back into reps mid-edit.
    public func isTimed(_ row: WorkoutExercise) -> Bool {
        if timedExercises.contains(row.id) { return true }
        if timedByDefault(row.exerciseID) { return true }
        // A typed or filled duration is read live (cheap); what Previous and the plan say is cached per row.
        let timed =
            (row.sets ?? []).contains { $0.durationSeconds != nil }
            || (derivedTimedLookups[row.id] ?? computeDerivedTimed(row))
        if timed { timedExercises.insert(row.id) }
        return timed
    }

    private func computeDerivedTimed(_ row: WorkoutExercise) -> Bool {
        let timed = sortedSets(of: row).contains {
            previous(for: $0)?.durationSeconds != nil || plan(for: $0)?.durationSeconds != nil
        }
        derivedTimedLookups[row.id] = timed
        return timed
    }

    /// Drops the cached Previous, plan and timed lookups. Called by every edit that can change which set takes which
    /// Previous or plan value (a set or exercise added, removed, replaced, reordered or regrouped, a set's kind, a row's
    /// unit), by every reload of the Previous values, and after a rollback.
    func invalidateLookups() {
        previousLookups.removeAll()
        planLookups.removeAll()
        derivedTimedLookups.removeAll()
    }

    /// Clears the loaded Previous values together with the lookups derived from them.
    func resetPrevious() {
        previousCache = [:]
        previousLoaded = []
        invalidateLookups()
    }

    // MARK: - Exercises

    /// Appends `info` with its defaults: a custom exercise's own unit, bar and rest if set, else Settings `defaultUnit`,
    /// an Olympic bar for barbells (none otherwise); three empty sets. Rest stays nil ("Default", read from Settings at each
    /// check) unless the exercise has its own.
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
                restSeconds: info.restSeconds
            )
            for index in 0..<Self.defaultSetCount { insertSet(into: row, position: index, kind: .normal) }
            added.append(row)
            position += 1
        }
        try commitRollingBack(workout, nil)
        return added
    }

    /// Replaces the exercise of `row` with `info`; sets, note, rest, unit and bar stay (the set values are not
    /// converted).
    public func replaceExercise(_ row: WorkoutExercise, with info: ExerciseInfo) throws {
        let workout = try owned(row)
        try loadPrevious(for: [info.id])
        row.exerciseID = info.id
        row.exerciseName = info.name
        timedExercises.remove(row.id)  // the new exercise decides again whether the row is timed
        try commitRollingBack(workout, row)
    }

    /// Removes `row` with its sets, renumbers positions and dissolves a superset left with one member.
    public func removeExercise(_ row: WorkoutExercise) throws {
        let workout = try owned(row)
        cancelRest(ownedBy: Set(sortedSets(of: row).map(\.id)), workout: workout)
        context.delete(row)
        let remaining = sortedExercises(of: workout).filter { $0 !== row }
        renumber(remaining)
        try commitRollingBack(workout, nil)
    }

    /// Rewrites exercise positions from `order`, which must contain each of the workout's exercises exactly once. A
    /// superset the move splits loses the moved member, and a non-member dropped inside a superset lands after it
    /// (``SupersetGrouping/reordered(_:to:moving:)``); `moving` is the dragged exercises when known.
    public func reorderExercises(_ order: [WorkoutExercise], moving: [WorkoutExercise] = []) throws {
        let workout = try activeWorkout()
        let current = sortedExercises(of: workout)
        guard order.count == current.count,
            Set(order.map(ObjectIdentifier.init)) == Set(current.map(ObjectIdentifier.init))
        else { throw ActiveWorkoutError.invalidOrder }
        let grouped = SupersetGrouping.reordered(
            current.map { (id: $0.id, group: $0.supersetGroup) },
            to: order.map(\.id),
            moving: moving.map(\.id)
        )
        let rows = Dictionary(order.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (position, item) in grouped.enumerated() {
            guard let row = rows[item.id] else { continue }
            row.position = position
            row.updatedAt = now()
            row.supersetGroup = item.group
        }
        try commitRollingBack(workout, nil)
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
        let (withValues, withoutValues) = uncheckedCounts(in: rows)
        return try makeSummary(
            workout: workout,
            kept: kept,
            end: now(),
            workoutNumber: try finishedCount(excluding: workout) + 1,
            uncheckedWithValues: withValues,
            uncheckedWithoutValues: withoutValues
        )
    }

    /// Which Finish dialog applies right now: the same answer as ``finishSummary()``'s `dialog`, from set counts alone
    /// (no PR scan over the history), for the Finish button.
    public func finishDialog() throws -> FinishDialog {
        let workout = try activeWorkout()
        let rows = sortedExercises(of: workout).map { ($0, sortedSets(of: $0)) }
        let (withValues, withoutValues) = uncheckedCounts(in: rows)
        let anyChecked = rows.contains { $0.1.contains(where: \.completed) }
        return Self.dialog(
            anyChecked: anyChecked,
            uncheckedWithValues: withValues,
            uncheckedWithoutValues: withoutValues
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
        // Same fill as `check(_:)`: typed values stay, empty fields take Previous, else the plan. Every fill is computed
        // before the first deletion: Previous and the plan find a set's position in the live relationships, so a dropped
        // set must not shift a later one.
        var fills: [ObjectIdentifier: (weight: Double?, reps: Int?, duration: Int?)] = [:]
        if unfinished == .complete {
            for row in rows {
                for set in sortedSets(of: row) where !set.completed && hasValues(set, in: row) {
                    fills[ObjectIdentifier(set)] = filledValues(of: set, in: row)
                }
            }
        }
        do {
            var keptRows: [WorkoutExercise] = []
            for row in rows {
                var survivors: [WorkoutSet] = []
                for set in sortedSets(of: row) {
                    if let filled = fills[ObjectIdentifier(set)] {
                        set.weight = filled.weight
                        set.reps = filled.reps
                        set.durationSeconds = filled.duration
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
        } catch {
            // A failed save must not leave the deletions and `finishedAt` behind: the table would re-read deleted
            // rows and a retry would walk deleted models. The engine still reports the (restored) workout.
            rollbackKeepingEdits(in: workout)
            throw error
        }
        // The workout is saved as finished: the engine lets go of it even if building the summary throws below.
        self.workout = nil
        resetPrevious()
        return try makeSummary(
            workout: workout,
            kept: kept,
            end: end,
            workoutNumber: try finishedCount(excluding: workout) + 1,
            uncheckedWithValues: 0,
            uncheckedWithoutValues: 0
        )
    }

    /// Deletes the workout with everything in it. The caller confirms first ("Discard workout?").
    public func discard() throws {
        let workout = try activeWorkout()
        // Cleared first so nothing observing the engine can read the model while it is being deleted.
        self.workout = nil
        context.delete(workout)
        do {
            try save()
        } catch {
            rollbackKeepingEdits(in: workout)
            self.workout = workout
            throw error
        }
        resetPrevious()
    }
}
