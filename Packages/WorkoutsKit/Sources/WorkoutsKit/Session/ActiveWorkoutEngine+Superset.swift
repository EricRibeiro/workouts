import Foundation
import SwiftData

// MARK: - Supersets and warm-ups

extension ActiveWorkoutEngine {
    /// Makes `rows` one superset (Create/Edit Superset, Save): the members are gathered next to each other where the
    /// first of them was, positions are rewritten, groups of fewer than two dissolve and groups renumber 1, 2, 3 by
    /// first appearance (``SupersetGrouping``). Fewer than two distinct rows change nothing but that dissolve and
    /// renumber pass.
    /// - Throws: ``ActiveWorkoutError/notInActiveWorkout`` when a row is not in the workout; nothing changes.
    public func makeSuperset(_ rows: [WorkoutExercise]) throws {
        let workout = try activeWorkout()
        for row in rows { _ = try owned(row) }
        let current = sortedExercises(of: workout)
        let result = SupersetGrouping.grouping(
            current.map { (id: $0.id, group: $0.supersetGroup) },
            members: rows.map(\.id)
        )
        let byID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stamp = now()
        for (position, entry) in result.enumerated() {
            guard let row = byID[entry.id] else { continue }
            guard row.position != position || row.supersetGroup != entry.group else { continue }
            row.position = position
            row.supersetGroup = entry.group
            row.updatedAt = stamp
        }
        try commitRollingBack(workout, nil)
    }

    /// Add Warm-up Sets: replaces the row's warm-up sets with the ``WarmupRamp`` for its first non-warm-up set that has
    /// a weight above 0, in the row's unit and bar. The ramp sits ahead of the working sets (kind warm-up, unchecked,
    /// weight and reps filled) and set positions are renumbered. Without such a working weight nothing changes; a
    /// working weight whose ramp is empty (45 lb on the 45 lb bar) still removes the old warm-ups.
    /// - Throws: ``ActiveWorkoutError/notInActiveWorkout`` when the row is not in the workout.
    public func addWarmupSets(to row: WorkoutExercise) throws {
        let workout = try owned(row)
        let existing = sortedSets(of: row)
        guard let working = existing.first(where: { $0.kind != .warmup && ($0.weight ?? 0) > 0 }),
            let weight = working.weight
        else { return }
        let ramp = WarmupRamp.steps(
            workingWeight: weight,
            unit: row.unit,
            barType: row.barType,
            customBarWeight: row.barWeight
        )
        let old = existing.filter { $0.kind == .warmup }
        cancelRest(ownedBy: Set(old.map(\.id)), workout: workout)
        for set in old { context.delete(set) }
        for (position, step) in ramp.enumerated() {
            let set = insertSet(into: row, position: position, kind: .warmup)
            set.weight = step.weight
            set.reps = step.reps
        }
        for (index, set) in existing.filter({ $0.kind != .warmup }).enumerated() {
            set.position = ramp.count + index
        }
        try commitRollingBack(workout, row)
    }
}
