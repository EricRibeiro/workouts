//
//  SetTableSources.swift
//  Workouts
//

import Foundation
import SwiftData
import WorkoutsKit

// MARK: - Active

/// The active workout (`ActiveWorkoutEngine`) as a set table: Previous and plan from the engine, check and rest through it.
/// Engine errors are swallowed here: a refused check (`emptySet`) just leaves the set unchecked; the shake and ring that
/// explain it belong to the logging screen (2.4).
struct EngineSetTableSource: SetTableDataSource {
    let engine: ActiveWorkoutEngine
    let store: ExerciseStore

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
            skip: { try? engine.skipRest() },
            add30: { try? engine.adjustRest(by: 30) }
        )
    }

    func cycleKind(of setID: UUID) {
        guard let set = set(setID) else { return }
        try? engine.setKind(set, to: SetInputFormat.nextKind(after: set.kind))
    }

    func applyPrevious(to setID: UUID) {
        guard let set = set(setID) else { return }
        _ = try? engine.applyPrevious(to: set)
    }

    func commitWeight(_ weight: Double?, for setID: UUID) {
        guard let set = set(setID) else { return }
        try? engine.setValues(set, weight: weight, reps: set.reps, durationSeconds: set.durationSeconds)
    }

    func commitReps(_ value: Int?, for setID: UUID) {
        guard let set = set(setID), let row = set.workoutExercise else { return }
        let timed = set.durationSeconds != nil || isTimed(row)
        try? engine.setValues(
            set,
            weight: set.weight,
            reps: timed ? set.reps : value,
            durationSeconds: timed ? value : set.durationSeconds
        )
    }

    func toggleCheck(of setID: UUID) {
        guard let set = set(setID) else { return }
        if set.completed {
            try? engine.uncheck(set)
        } else {
            try? engine.check(set)
        }
    }

    func addSet(to sectionID: UUID) {
        guard let row = exercises.first(where: { $0.id == sectionID }) else { return }
        _ = try? engine.addSet(to: row)
    }

    func deleteSet(_ setID: UUID) {
        guard let set = set(setID) else { return }
        try? engine.removeSet(set)
    }

    func reorder(_ order: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let ordered = order.compactMap { byID[$0] }
        guard ordered.count == byID.count else { return }
        try? engine.reorderExercises(ordered)
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

/// A template as a set table: planned weights and reps are the values, there is no Previous and no check. Edits save to
/// the template's own context.
struct TemplateSetTableSource: SetTableDataSource {
    let template: Template
    let context: ModelContext
    let store: ExerciseStore

    var mode: SetTableMode { .template }

    private var exercises: [TemplateExercise] {
        (template.exercises ?? []).sorted { $0.position < $1.position }
    }

    var sections: [SetTableSection] {
        exercises.map { row in
            let sets = sorted(row.sets)
            let weightType = store.exercise(id: row.exerciseID)?.weightType ?? .weighted
            let timed = sets.contains { $0.durationSeconds != nil }
            return SetTableSection(
                id: row.id,
                exerciseID: row.exerciseID,
                name: row.exerciseName,
                supersetGroup: row.supersetGroup,
                note: row.note,
                restSeconds: row.restSeconds,
                rows: sets.enumerated().map { index, set in
                    SetRowModel(
                        id: set.id,
                        number: index + 1,
                        kind: set.kind,
                        weightText: SetInputFormat.weightText(set.weight),
                        repsText: SetInputFormat.countText(timed ? set.durationSeconds : set.reps),
                        unit: row.unit,
                        weightType: weightType,
                        measure: timed ? .duration : .reps,
                        showsPrevious: false,
                        showsCheck: false
                    )
                }
            )
        }
    }

    func cycleKind(of setID: UUID) {
        guard let set = set(setID) else { return }
        set.kind = SetInputFormat.nextKind(after: set.kind)
        touch(set.templateExercise)
    }

    func applyPrevious(to setID: UUID) {}

    func commitWeight(_ weight: Double?, for setID: UUID) {
        guard let set = set(setID) else { return }
        set.weight = weight
        touch(set.templateExercise)
    }

    func commitReps(_ value: Int?, for setID: UUID) {
        guard let set = set(setID) else { return }
        if set.durationSeconds != nil {
            set.durationSeconds = value
        } else {
            set.reps = value
        }
        touch(set.templateExercise)
    }

    func toggleCheck(of setID: UUID) {}

    func addSet(to sectionID: UUID) {
        guard let row = exercises.first(where: { $0.id == sectionID }) else { return }
        let last = sorted(row.sets).last
        let added = TemplateSet(
            position: (last?.position ?? -1) + 1,
            kind: last.map { $0.kind == .warmup ? .normal : $0.kind } ?? .normal,
            weight: last?.weight,
            reps: last?.reps,
            durationSeconds: last?.durationSeconds,
            distanceMeters: last?.distanceMeters,
            templateExercise: row
        )
        context.insert(added)
        touch(row)
    }

    func deleteSet(_ setID: UUID) {
        guard let set = set(setID), let row = set.templateExercise else { return }
        context.delete(set)
        for (position, remaining) in sorted(row.sets).filter({ $0 !== set }).enumerated() {
            remaining.position = position
        }
        touch(row)
    }

    func reorder(_ order: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        guard order.count == byID.count else { return }
        for (position, id) in order.enumerated() { byID[id]?.position = position }
        touch(nil)
    }

    private func set(_ id: UUID) -> TemplateSet? {
        exercises.lazy.flatMap { $0.sets ?? [] }.first { $0.id == id }
    }

    private func touch(_ row: TemplateExercise?) {
        let now = Date()
        row?.updatedAt = now
        template.updatedAt = now
        try? context.save()
    }
}

// MARK: - Past

/// A finished workout in the History editor. Stub for task 3.x: it lists the sets (values only, no Previous, no check) and
/// ignores every edit until the past-workout editor fills the actions in.
struct PastSetTableSource: SetTableDataSource {
    let workout: Workout
    let store: ExerciseStore

    var mode: SetTableMode { .past }

    var sections: [SetTableSection] {
        (workout.exercises ?? []).sorted { $0.position < $1.position }.map { row in
            let sets = sorted(row.sets)
            let weightType = store.exercise(id: row.exerciseID)?.weightType ?? .weighted
            let timed = sets.contains { $0.durationSeconds != nil }
            return SetTableSection(
                id: row.id,
                exerciseID: row.exerciseID,
                name: row.exerciseName,
                supersetGroup: row.supersetGroup,
                note: row.note,
                restSeconds: nil,
                rows: sets.enumerated().map { index, set in
                    SetRowModel(
                        id: set.id,
                        number: index + 1,
                        kind: set.kind,
                        weightText: SetInputFormat.weightText(set.weight),
                        repsText: SetInputFormat.countText(timed ? set.durationSeconds : set.reps),
                        unit: row.unit,
                        weightType: weightType,
                        measure: timed ? .duration : .reps,
                        showsPrevious: false,
                        showsCheck: false
                    )
                }
            )
        }
    }

    func cycleKind(of setID: UUID) {}
    func applyPrevious(to setID: UUID) {}
    func commitWeight(_ weight: Double?, for setID: UUID) {}
    func commitReps(_ value: Int?, for setID: UUID) {}
    func toggleCheck(of setID: UUID) {}
    func addSet(to sectionID: UUID) {}
    func deleteSet(_ setID: UUID) {}
    func reorder(_ order: [UUID]) {}
}

// MARK: - Shared helpers

private func sorted(_ sets: [WorkoutSet]?) -> [WorkoutSet] {
    (sets ?? []).sorted { $0.position < $1.position }
}

private func sorted(_ sets: [TemplateSet]?) -> [TemplateSet] {
    (sets ?? []).sorted { $0.position < $1.position }
}

/// Greyed hint of a weight cell: the value, else `–`.
private func placeholder(weight: Double?) -> String {
    weight.map { SetInputFormat.weightText($0) } ?? "–"
}

private func placeholder(count: Int?) -> String {
    count.map { SetInputFormat.countText($0) } ?? "–"
}
