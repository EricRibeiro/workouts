import Foundation
import SwiftData

/// The "Update Template?" decision after finishing a workout that came from a template (`active-workout.md` section 3,
/// Finish): how the finished workout differs from its template, and what each answer does to the template.
///
/// *Structure* is the exercise list (which exercises, in which order), each exercise's sets (count and kinds) and the
/// superset grouping. *Values* are the planned weight, reps, duration and distance of the sets.
public enum TemplateUpdate {
    /// How the finished workout differs from its template.
    public enum Kind: Sendable, Equatable {
        /// Same exercises, sets and values: nothing to ask.
        case none
        /// Same exercises and sets, different weights, reps or durations: "Update Template" / "Keep Original Template".
        case valuesOnly
        /// Exercises or sets were added, removed or reordered: the three-way question.
        case structure
    }

    /// The answer to the dialog.
    public enum Choice: Sendable, Equatable {
        /// Copy the workout's values into the template's matching exercises and sets; its structure stays.
        case valuesOnly
        /// Make the template match the workout: structure and values.
        case templateAndValues
        /// Leave the template alone.
        case keep
    }

    /// Compares the finished `workout` with `template`. Exercises are read in position order.
    public static func diff(template: Template, workout: Workout) -> Kind {
        let planned = orderedRows(of: template)
        let done = orderedRows(of: workout)
        guard planned.count == done.count else { return .structure }
        guard normalizedGroups(planned.map(\.supersetGroup)) == normalizedGroups(done.map(\.supersetGroup)) else {
            return .structure
        }
        var valuesDiffer = false
        for (plan, row) in zip(planned, done) {
            guard plan.exerciseID == row.exerciseID else { return .structure }
            if barsDiffer(plan, row) { valuesDiffer = true }
            let plannedSets = orderedSets(of: plan)
            let doneSets = orderedSets(of: row)
            guard plannedSets.count == doneSets.count else { return .structure }
            for (plannedSet, doneSet) in zip(plannedSets, doneSets) {
                guard plannedSet.kind == doneSet.kind else { return .structure }
                if !sameValues(plannedSet, plan.unit, doneSet, row.unit) { valuesDiffer = true }
            }
        }
        return valuesDiffer ? .valuesOnly : .none
    }

    /// Applies `choice` to `template` from the finished `workout` and saves. On a failed save the context is rolled
    /// back and the error rethrown.
    public static func apply(
        _ choice: Choice,
        template: Template,
        workout: Workout,
        in context: ModelContext
    ) throws {
        switch choice {
        case .keep:
            return
        case .valuesOnly:
            copyValues(from: workout, to: template)
        case .templateAndValues:
            mirror(workout, into: template, in: context)
        }
        template.updatedAt = Date()
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: Values

    /// Pairs template exercises with workout exercises of the same id (each used once, in order) and copies the values
    /// of the sets they share. Sets pair by kind (the n-th warm-up with the n-th warm-up, the n-th other set with the
    /// n-th other set), so warm-ups added during the workout never shift working-set values; only checked workout sets
    /// give values, and a template set with no counterpart keeps its own. The template's structure never changes.
    private static func copyValues(from workout: Workout, to template: Template) {
        var available = orderedRows(of: workout)
        for plan in orderedRows(of: template) {
            guard let index = available.firstIndex(where: { $0.exerciseID == plan.exerciseID }) else { continue }
            let row = available.remove(at: index)
            plan.unit = row.unit
            plan.barType = row.barType
            plan.barWeight = row.barWeight
            plan.updatedAt = Date()
            let done = orderedSets(of: row)
            for isWarmup in [true, false] {
                let targets = orderedSets(of: plan).filter { ($0.kind == .warmup) == isWarmup }
                let sources = done.filter { ($0.kind == .warmup) == isWarmup }
                for (plannedSet, doneSet) in zip(targets, sources) where doneSet.completed {
                    copy(doneSet, into: plannedSet)
                }
            }
        }
    }

    private static func copy(_ source: WorkoutSet, into target: TemplateSet) {
        target.weight = source.weight
        target.reps = source.reps
        target.durationSeconds = source.durationSeconds
        target.distanceMeters = source.distanceMeters
    }

    // MARK: Structure

    /// Rebuilds the template's exercises and sets from the workout. A template exercise with the same exercise id is
    /// reused (it keeps its note and rest); the others are created or deleted.
    private static func mirror(_ workout: Workout, into template: Template, in context: ModelContext) {
        var reusable = orderedRows(of: template)
        for (position, row) in orderedRows(of: workout).enumerated() {
            let plan: TemplateExercise
            if let index = reusable.firstIndex(where: { $0.exerciseID == row.exerciseID }) {
                plan = reusable.remove(at: index)
            } else {
                plan = TemplateExercise(
                    exerciseID: row.exerciseID,
                    exerciseName: row.exerciseName,
                    note: row.note,
                    restSeconds: row.restSeconds
                )
                context.insert(plan)
                plan.template = template
            }
            plan.position = position
            plan.supersetGroup = row.supersetGroup
            plan.unit = row.unit
            plan.barType = row.barType
            plan.barWeight = row.barWeight
            plan.updatedAt = Date()
            mirrorSets(of: row, into: plan, in: context)
        }
        for stale in reusable { context.delete(stale) }
    }

    private static func mirrorSets(of row: WorkoutExercise, into plan: TemplateExercise, in context: ModelContext) {
        var existing = orderedSets(of: plan)
        for (position, doneSet) in orderedSets(of: row).enumerated() {
            let target: TemplateSet
            if existing.isEmpty {
                target = TemplateSet()
                context.insert(target)
                target.templateExercise = plan
            } else {
                target = existing.removeFirst()
            }
            target.position = position
            target.kind = doneSet.kind
            copy(doneSet, into: target)
        }
        for stale in existing { context.delete(stale) }
    }

    // MARK: Reading

    private static func orderedRows(of template: Template) -> [TemplateExercise] {
        (template.exercises ?? []).sorted {
            $0.position != $1.position ? $0.position < $1.position : $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func orderedRows(of workout: Workout) -> [WorkoutExercise] {
        (workout.exercises ?? []).sorted {
            $0.position != $1.position ? $0.position < $1.position : $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func orderedSets(of plan: TemplateExercise) -> [TemplateSet] {
        (plan.sets ?? []).sorted {
            $0.position != $1.position ? $0.position < $1.position : $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func orderedSets(of row: WorkoutExercise) -> [WorkoutSet] {
        (row.sets ?? []).sorted {
            $0.position != $1.position ? $0.position < $1.position : $0.id.uuidString < $1.id.uuidString
        }
    }

    /// Superset numbers renamed by first appearance, so groups 2 and 5 match groups 1 and 2; nil stays nil.
    private static func normalizedGroups(_ groups: [Int?]) -> [Int?] {
        var names: [Int: Int] = [:]
        return groups.map { group in
            guard let group else { return nil }
            if let name = names[group] { return name }
            let name = names.count + 1
            names[group] = name
            return name
        }
    }

    /// A different bar type, or a different custom bar weight (compared across units), is a change. The unit alone is not:
    /// the same weights in another unit are the same load.
    private static func barsDiffer(_ plan: TemplateExercise, _ row: WorkoutExercise) -> Bool {
        guard plan.barType == row.barType else { return true }
        guard plan.barType == .custom else { return false }
        return !weightsEqual(plan.barWeight ?? 0, plan.unit, row.barWeight ?? 0, row.unit)
    }

    /// Weights compare across units; a missing weight, reps or duration equals zero.
    private static func sameValues(
        _ plan: TemplateSet,
        _ planUnit: WeightUnit,
        _ done: WorkoutSet,
        _ doneUnit: WeightUnit
    ) -> Bool {
        weightsEqual(plan.weight ?? 0, planUnit, done.weight ?? 0, doneUnit)
            && (plan.reps ?? 0) == (done.reps ?? 0)
            && (plan.durationSeconds ?? 0) == (done.durationSeconds ?? 0)
            && abs((plan.distanceMeters ?? 0) - (done.distanceMeters ?? 0)) < 0.005
    }
}
