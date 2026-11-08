import Foundation
import SwiftData

// MARK: - Block edits (the exercise header menu, task 3.6d)

extension ActiveWorkoutEngine {
    /// Sets the row's note, trimmed (whitespace-only clears it). Restores the previous note (and timestamps) when the save
    /// fails, so a sheet that is cancelled after the error does not leave the typed text showing.
    /// - Throws: ``ActiveWorkoutError/notInActiveWorkout`` when the row is not in the workout.
    public func setNote(_ text: String, for row: WorkoutExercise) throws {
        let workout = try owned(row)
        let (previousNote, previousRowStamp, previousWorkoutStamp) = (row.note, row.updatedAt, workout.updatedAt)
        row.note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try commit(workout, row)
        } catch {
            row.note = previousNote
            row.updatedAt = previousRowStamp
            workout.updatedAt = previousWorkoutStamp
            throw error
        }
    }

    /// Update Rest Timer: the row's rest in seconds: 0 = Off (no timer), nil = Default (the Settings rest). Only this row changes (each row rests by its own
    /// length). A single-value edit.
    /// - Throws: ``ActiveWorkoutError/notInActiveWorkout`` when the row is not in the workout.
    public func setRest(_ seconds: Int?, for row: WorkoutExercise) throws {
        let workout = try owned(row)
        row.restSeconds = seconds
        try commit(workout, row)
    }

    /// Preferences: the row's weight unit. Set values are not converted, but a custom bar's weight is (rounded to 0.5,
    /// like a converted set weight). A single-value edit.
    /// - Throws: ``ActiveWorkoutError/notInActiveWorkout`` when the row is not in the workout.
    public func setUnit(_ unit: WeightUnit, for row: WorkoutExercise) throws {
        let workout = try owned(row)
        if row.unit != unit, row.barType == .custom, let bar = row.barWeight {
            row.barWeight = convertedWeight(bar, from: row.unit, to: unit)
        }
        row.unit = unit
        try commit(workout, row)
    }

    /// Preferences: the row's bar. `weight` is the custom bar's weight (only a `.custom` bar reads it). A single-value
    /// edit.
    /// - Throws: ``ActiveWorkoutError/notInActiveWorkout`` when the row is not in the workout.
    public func setBar(_ type: BarType, weight: Double?, for row: WorkoutExercise) throws {
        let workout = try owned(row)
        row.barType = type
        row.barWeight = weight
        try commit(workout, row)
    }

    /// Takes `row` out of its superset; a member from the middle of the group moves to just after it so the group stays
    /// contiguous (``SupersetGrouping/removingFromGroup(_:in:)``). A group left with one member dissolves and the groups
    /// renumber 1, 2, 3 by first appearance. A row in no superset changes nothing. Rolls back when the save fails.
    /// - Throws: ``ActiveWorkoutError/notInActiveWorkout`` when the row is not in the workout.
    public func removeFromSuperset(_ row: WorkoutExercise) throws {
        let workout = try owned(row)
        guard row.supersetGroup != nil else { return }
        let current = sortedExercises(of: workout)
        let result = SupersetGrouping.removingFromGroup(
            row.id,
            in: current.map { (id: $0.id, group: $0.supersetGroup) }
        )
        let byID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stamp = now()
        for (position, entry) in result.enumerated() {
            guard let member = byID[entry.id], member.supersetGroup != entry.group || member.position != position
            else { continue }
            member.position = position
            member.supersetGroup = entry.group
            member.updatedAt = stamp
        }
        try commitRollingBack(workout, nil)
    }
}
