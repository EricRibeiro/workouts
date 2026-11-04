import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

/// A failed save must leave the workout exactly as it was (R-05), and `finishDialog()` must agree with
/// `finishSummary().dialog` (R-17). Failures are injected through the engine's internal `saveHook`.
@Suite struct EngineSaveFailureTests {
    typealias Rig = EngineTests.Rig

    struct SaveFailed: Error {}

    private func rows(_ workout: Workout) -> [WorkoutExercise] {
        (workout.exercises ?? []).sorted { $0.position < $1.position }
    }

    private func sets(_ row: WorkoutExercise) -> [WorkoutSet] {
        (row.sets ?? []).sorted { $0.position < $1.position }
    }

    /// Squat with one checked set and two unchecked (one with values), plus an untouched curl row.
    private func startedWorkout(_ rig: Rig) throws -> (ActiveWorkoutEngine, Workout, WorkoutExercise) {
        let engine = try rig.makeEngine()
        let workout = try engine.startEmpty()
        let squat = try engine.addExercise(try rig.info(LibraryFixture.squat))
        _ = try engine.addExercise(try rig.info(LibraryFixture.curl))
        try engine.setValues(sets(squat)[0], weight: 100, reps: 5, durationSeconds: nil)
        try engine.check(sets(squat)[0])
        try engine.setValues(sets(squat)[1], weight: 100, reps: 5, durationSeconds: nil)
        return (engine, workout, squat)
    }

    /// Everything the table reads, as plain values.
    private func snapshot(_ workout: Workout) -> [String] {
        rows(workout).flatMap { row in
            ["\(row.exerciseID) p\(row.position)"]
                + sets(row).map { "\($0.id) p\($0.position) c\($0.completed) w\($0.weight ?? -1) r\($0.reps ?? -1)" }
        } + ["finished \(workout.finishedAt != nil)"]
    }

    private func expectUnchanged(
        _ rig: Rig,
        _ engine: ActiveWorkoutEngine,
        _ workout: Workout,
        _ before: [String],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        #expect(engine.workout === workout, sourceLocation: sourceLocation)
        #expect(!workout.isDeleted, sourceLocation: sourceLocation)
        #expect(snapshot(workout) == before, sourceLocation: sourceLocation)
        #expect(
            try rig.context.fetchCount(FetchDescriptor<WorkoutSet>()) == before.count - 3,
            sourceLocation: sourceLocation
        )
        #expect(try !rig.context.hasChanges, sourceLocation: sourceLocation)
    }

    @Test func failedFinishRollsBackAndRetrySucceeds() throws {
        let rig = try Rig()
        let (engine, workout, _) = try startedWorkout(rig)
        let before = snapshot(workout)
        engine.saveHook = { throw SaveFailed() }
        #expect(throws: SaveFailed.self) { try engine.finish(unfinished: .discard) }
        try expectUnchanged(rig, engine, workout, before)

        engine.saveHook = nil
        let summary = try engine.finish(unfinished: .discard)
        #expect(summary.setCount == 1 && summary.exerciseCount == 1)
        #expect(engine.workout == nil && workout.finishedAt != nil)
    }

    @Test func failedFinishWithCompleteRollsBackCompletedFlags() throws {
        let rig = try Rig()
        let (engine, workout, squat) = try startedWorkout(rig)
        let before = snapshot(workout)
        engine.saveHook = { throw SaveFailed() }
        #expect(throws: SaveFailed.self) { try engine.finish(unfinished: .complete) }
        try expectUnchanged(rig, engine, workout, before)
        #expect(sets(squat).filter(\.completed).count == 1)
    }

    @Test func failedDiscardRollsBackAndKeepsTheWorkout() throws {
        let rig = try Rig()
        let (engine, workout, _) = try startedWorkout(rig)
        let before = snapshot(workout)
        engine.saveHook = { throw SaveFailed() }
        #expect(throws: SaveFailed.self) { try engine.discard() }
        try expectUnchanged(rig, engine, workout, before)

        engine.saveHook = nil
        try engine.discard()
        #expect(engine.workout == nil)
        #expect(try rig.context.fetchCount(FetchDescriptor<Workout>()) == 0)
    }

    @Test func failedStartLeavesNoWorkoutBehind() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        engine.saveHook = { throw SaveFailed() }
        #expect(throws: SaveFailed.self) { try engine.startEmpty() }
        #expect(engine.workout == nil)
        #expect(try rig.context.fetchCount(FetchDescriptor<Workout>()) == 0)
        #expect(try !rig.context.hasChanges)

        engine.saveHook = nil
        try engine.startEmpty()
        #expect(engine.workout != nil)
    }

    @Test func failedRemoveSetRestoresTheSet() throws {
        let rig = try Rig()
        let (engine, workout, squat) = try startedWorkout(rig)
        let before = snapshot(workout)
        engine.saveHook = { throw SaveFailed() }
        #expect(throws: SaveFailed.self) { try engine.removeSet(sets(squat)[0]) }
        try expectUnchanged(rig, engine, workout, before)
    }

    @Test func failedRemoveExerciseRestoresTheRow() throws {
        let rig = try Rig()
        let (engine, workout, squat) = try startedWorkout(rig)
        let before = snapshot(workout)
        engine.saveHook = { throw SaveFailed() }
        #expect(throws: SaveFailed.self) { try engine.removeExercise(squat) }
        try expectUnchanged(rig, engine, workout, before)
        #expect(rows(workout).count == 2)
    }

    @Test func failedAddExerciseAndAddSetLeaveNothingBehind() throws {
        let rig = try Rig()
        let (engine, workout, squat) = try startedWorkout(rig)
        let before = snapshot(workout)
        engine.saveHook = { throw SaveFailed() }
        #expect(throws: SaveFailed.self) { try engine.addExercise(try rig.info(LibraryFixture.curl)) }
        #expect(throws: SaveFailed.self) { try engine.addSet(to: squat) }
        try expectUnchanged(rig, engine, workout, before)
    }

    @Test func failedReorderRestoresPositions() throws {
        let rig = try Rig()
        let (engine, workout, _) = try startedWorkout(rig)
        let before = snapshot(workout)
        engine.saveHook = { throw SaveFailed() }
        #expect(throws: SaveFailed.self) { try engine.reorderExercises(rows(workout).reversed()) }
        try expectUnchanged(rig, engine, workout, before)
    }

    @Test func failedWarmupAndSupersetRestoreTheWorkout() throws {
        let rig = try Rig()
        let (engine, workout, squat) = try startedWorkout(rig)
        let before = snapshot(workout)
        engine.saveHook = { throw SaveFailed() }
        #expect(throws: SaveFailed.self) { try engine.addWarmupSets(to: squat) }
        #expect(throws: SaveFailed.self) { try engine.makeSuperset(rows(workout)) }
        try expectUnchanged(rig, engine, workout, before)
        #expect(rows(workout).allSatisfy { $0.supersetGroup == nil })
    }

    // MARK: finishDialog

    @Test func finishDialogAgreesWithFinishSummary() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))

        func check() throws {
            #expect(try engine.finishDialog() == engine.finishSummary().dialog)
        }
        // Nothing checked, with and without typed values.
        try check()
        #expect(try engine.finishDialog() == .nothingLogged)
        try engine.setValues(sets(row)[0], weight: 50, reps: 5, durationSeconds: nil)
        try check()
        #expect(try engine.finishDialog() == .nothingLogged)
        // One checked, one unchecked with values, one empty.
        try engine.check(sets(row)[0])
        try engine.setValues(sets(row)[1], weight: 50, reps: nil, durationSeconds: nil)
        try check()
        #expect(try engine.finishDialog() == .unfinishedWithValues(count: 1))
        // Only empty unchecked sets left.
        try engine.setValues(sets(row)[1], weight: nil, reps: nil, durationSeconds: nil)
        try check()
        #expect(try engine.finishDialog() == .unfinishedWithoutValues(count: 2))
        // Everything checked.
        try engine.removeSet(sets(row)[2])
        try engine.removeSet(sets(row)[1])
        try check()
        #expect(try engine.finishDialog() == FinishDialog.none)
    }

    @Test func finishDialogWithoutAWorkoutThrows() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        #expect(throws: ActiveWorkoutError.noActiveWorkout) { try engine.finishDialog() }
    }
}
