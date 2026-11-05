//
//  SetTableSources.swift
//  Workouts
//

import Foundation
import SwiftData
import SwiftUI
import WorkoutsKit

// MARK: - Active

/// The active workout (`ActiveWorkoutEngine`) as a set table: Previous and plan from the engine, check and rest through it.
/// Engine errors go to `errors` (the save-error alert), except that a refused check (`emptySet`) is the normal "nothing to
/// record" path: it leaves the set unchecked and `toggleCheck` returns false so the row can show the refusal.
struct EngineSetTableSource: SetTableDataSource {
    let engine: ActiveWorkoutEngine
    let store: ExerciseStore
    /// Where failures are reported; `nil` (previews, the gallery) drops them.
    var errors: SaveErrors?

    var mode: SetTableMode { .active }

    private var exercises: [WorkoutExercise] {
        (engine.workout?.exercises ?? []).sorted { $0.position < $1.position }
    }

    var sections: [SetTableSection] {
        exercises.map { row in
            let sets = sorted(row.sets)
            let weightType = store.exercise(id: row.exerciseID)?.weightType ?? .weighted
            let timed =
                sets.contains { $0.durationSeconds != nil }
                || sets.contains {
                    engine.previous(for: $0)?.durationSeconds != nil
                }
            return SetTableSection(
                id: row.id,
                exerciseID: row.exerciseID,
                name: row.exerciseName,
                supersetGroup: row.supersetGroup,
                note: row.note,
                restSeconds: row.restSeconds,
                rows: sets.enumerated().map { index, set in
                    let previous = engine.previous(for: set)
                    let plan = engine.plan(for: set)
                    // The placeholder is what checking an empty set would fill in: Previous first, else the plan.
                    return SetRowModel(
                        id: set.id,
                        number: index + 1,
                        kind: set.kind,
                        previousText: SetInputFormat.previousText(previous, unit: row.unit),
                        weightText: SetInputFormat.weightText(set.weight),
                        repsText: SetInputFormat.countText(timed ? set.durationSeconds : set.reps),
                        isChecked: set.completed,
                        canCheck: engine.canCheck(set),
                        weightPlaceholder: placeholder(
                            weight: previous?.weight ?? plan?.weight
                        ),
                        repsPlaceholder: placeholder(
                            count: timed
                                ? (previous?.durationSeconds ?? plan?.durationSeconds)
                                : (previous?.reps ?? plan?.reps)
                        ),
                        unit: row.unit,
                        weightType: weightType,
                        measure: timed ? .duration : .reps
                    )
                }
            )
        }
    }

    var checkedSetCount: Int {
        exercises.reduce(0) { $0 + ($1.sets ?? []).filter(\.completed).count }
    }

    var rest: SetTableRest? {
        guard let endsAt = engine.restTimer.endsAt else { return nil }
        return SetTableRest(
            endsAt: endsAt,
            skip: { perform { try engine.skipRest() } },
            add30: { perform { try engine.adjustRest(by: 30) } }
        )
    }

    func cycleKind(of setID: UUID) {
        guard let set = set(setID) else { return }
        perform { try engine.setKind(set, to: SetInputFormat.nextKind(after: set.kind)) }
    }

    func applyPrevious(to setID: UUID) {
        guard let set = set(setID) else { return }
        perform { _ = try engine.applyPrevious(to: set) }
    }

    func commitWeight(_ weight: Double?, for setID: UUID) {
        guard let set = set(setID) else { return }
        perform { try engine.setValues(set, weight: weight, reps: set.reps, durationSeconds: set.durationSeconds) }
    }

    func commitReps(_ value: Int?, for setID: UUID) {
        guard let set = set(setID), let row = set.workoutExercise else { return }
        let timed = set.durationSeconds != nil || isTimed(row)
        perform {
            try engine.setValues(
                set,
                weight: set.weight,
                reps: timed ? set.reps : value,
                durationSeconds: timed ? value : set.durationSeconds
            )
        }
    }

    @discardableResult
    func toggleCheck(of setID: UUID) -> Bool {
        guard let set = set(setID) else { return true }
        do {
            if set.completed {
                try engine.uncheck(set)
            } else {
                try engine.check(set)
            }
            return true
        } catch ActiveWorkoutError.emptySet {
            // The refusal, not a failure: the row shows it.
            return false
        } catch {
            errors?.report(error)
            return false
        }
    }

    func addSet(to sectionID: UUID) {
        guard let row = exercises.first(where: { $0.id == sectionID }) else { return }
        perform { _ = try engine.addSet(to: row) }
    }

    func deleteSet(_ setID: UUID) {
        guard let set = set(setID) else { return }
        perform { try engine.removeSet(set) }
    }

    func reorder(_ order: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let ordered = order.compactMap { byID[$0] }
        guard ordered.count == byID.count else { return }
        perform { try engine.reorderExercises(ordered) }
    }

    /// Runs an engine call and reports a failure.
    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errors?.report(error)
        }
    }

    private func set(_ id: UUID) -> WorkoutSet? {
        exercises.lazy.flatMap { $0.sets ?? [] }.first { $0.id == id }
    }

    /// An exercise is timed when any of its sets, or the Previous behind them, recorded a duration.
    private func isTimed(_ row: WorkoutExercise) -> Bool {
        let sets = sorted(row.sets)
        return sets.contains { $0.durationSeconds != nil }
            || sets.contains {
                engine.previous(for: $0)?.durationSeconds != nil
            }
    }
}

// MARK: - Template

/// A template in the editor (task 3.4): the editor's `TemplateDraft` as a set table. Planned weights and reps are the
/// values; there is no Previous and no check. Every edit goes to the draft, which the editor's Save writes to the model in
/// one go.
struct TemplateSetTableSource: SetTableDataSource {
    @Binding var draft: TemplateDraft
    let store: ExerciseStore

    var mode: SetTableMode { .template }

    var sections: [SetTableSection] {
        draft.exercises.map { row in
            let weightType = store.exercise(id: row.exerciseID)?.weightType ?? .weighted
            return SetTableSection(
                id: row.id,
                exerciseID: row.exerciseID,
                name: row.name,
                supersetGroup: row.supersetGroup,
                note: row.note,
                restSeconds: row.restSeconds,
                rows: row.sets.enumerated().map { index, set in
                    SetRowModel(
                        id: set.id,
                        number: index + 1,
                        kind: set.kind,
                        weightText: SetInputFormat.weightText(set.weight),
                        repsText: SetInputFormat.countText(row.isTimed ? set.durationSeconds : set.reps),
                        unit: row.unit,
                        weightType: weightType,
                        measure: row.isTimed ? .duration : .reps,
                        showsPrevious: false,
                        showsCheck: false
                    )
                }
            )
        }
    }

    func cycleKind(of setID: UUID) { draft.cycleKind(of: setID) }
    func applyPrevious(to setID: UUID) {}
    func commitWeight(_ weight: Double?, for setID: UUID) { draft.setWeight(weight, for: setID) }
    func commitReps(_ value: Int?, for setID: UUID) { draft.setCount(value, for: setID) }
    @discardableResult
    func toggleCheck(of setID: UUID) -> Bool { true }
    func addSet(to sectionID: UUID) { draft.addSet(to: sectionID) }
    func deleteSet(_ setID: UUID) { draft.deleteSet(setID) }
    func reorder(_ order: [UUID]) { draft.reorder(order) }
}

// MARK: - Past

/// A finished workout in the History editor (task 5.6): the editor's `PastWorkoutDraft` as a set table. Values only, no
/// Previous and no check; every edit goes to the draft, which the editor's Save writes to the model in one go.
struct PastSetTableSource: SetTableDataSource {
    @Binding var draft: PastWorkoutDraft
    let store: ExerciseStore

    var mode: SetTableMode { .past }

    var sections: [SetTableSection] {
        draft.exercises.map { row in
            let weightType = store.exercise(id: row.exerciseID)?.weightType ?? .weighted
            return SetTableSection(
                id: row.id,
                exerciseID: row.exerciseID,
                name: row.name,
                supersetGroup: row.supersetGroup,
                note: row.note,
                restSeconds: nil,
                rows: row.sets.enumerated().map { index, set in
                    SetRowModel(
                        id: set.id,
                        number: index + 1,
                        kind: set.kind,
                        weightText: SetInputFormat.weightText(set.weight),
                        repsText: SetInputFormat.countText(row.isTimed ? set.durationSeconds : set.reps),
                        unit: row.unit,
                        weightType: weightType,
                        measure: row.isTimed ? .duration : .reps,
                        showsPrevious: false,
                        showsCheck: false
                    )
                }
            )
        }
    }

    func cycleKind(of setID: UUID) { draft.cycleKind(of: setID) }
    func applyPrevious(to setID: UUID) {}
    func commitWeight(_ weight: Double?, for setID: UUID) { draft.setWeight(weight, for: setID) }
    func commitReps(_ value: Int?, for setID: UUID) { draft.setCount(value, for: setID) }
    @discardableResult
    func toggleCheck(of setID: UUID) -> Bool { true }
    func addSet(to sectionID: UUID) { draft.addSet(to: sectionID) }
    func deleteSet(_ setID: UUID) { draft.deleteSet(setID) }
    func reorder(_ order: [UUID]) { draft.reorder(order) }
}

// MARK: - Shared helpers

private func sorted(_ sets: [WorkoutSet]?) -> [WorkoutSet] {
    (sets ?? []).sorted { $0.position < $1.position }
}

/// Greyed hint of a weight cell: the value, else `–`.
private func placeholder(weight: Double?) -> String {
    weight.map { SetInputFormat.weightText($0) } ?? "–"
}

private func placeholder(count: Int?) -> String {
    count.map { SetInputFormat.countText($0) } ?? "–"
}
