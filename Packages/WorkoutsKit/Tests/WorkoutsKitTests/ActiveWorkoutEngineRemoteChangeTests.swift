import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

/// A merge from another device can delete or finish the workout this device is logging (P-01), and a failed save while
/// clearing an expired rest at launch must not fail the engine (P-02).
@Suite struct EngineRemoteChangeTests {
    typealias Rig = EngineTests.Rig

    struct SaveFailed: Error {}

    /// What CloudKit does to the main context: another context on the same container saves the change.
    private func mutateElsewhere(_ rig: Rig, _ change: (Workout, ModelContext) -> Void) throws {
        let other = ModelContext(rig.container)
        let remote = try #require(try other.fetch(Workout.inProgress).first)
        change(remote, other)
        try other.save()
    }

    @Test func deletedRunningWorkoutIsDroppedByTheRemoteChangeHandler() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        try engine.addExercise(try rig.info(LibraryFixture.squat))

        try mutateElsewhere(rig) { remote, other in other.delete(remote) }
        // Until the main context refreshes it the model looks alive; the handler asks the store, not the model.
        try engine.reloadAfterRemoteChange()
        #expect(engine.workout == nil)
        #expect(engine.liveWorkout == nil)
        #expect(throws: ActiveWorkoutError.noActiveWorkout) { try engine.activeWorkout() }
        #expect(try rig.context.fetchCount(FetchDescriptor<Workout>()) == 0)
        // Recovered: a new workout can start.
        let next = try engine.startEmpty()
        #expect(engine.workout === next)
    }

    @Test func deletedInTheMainContextIsNotActive() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let running = try engine.startEmpty()
        rig.context.delete(running)
        try rig.context.save()
        #expect(engine.liveWorkout == nil)
        #expect(throws: ActiveWorkoutError.noActiveWorkout) { try engine.activeWorkout() }
        try engine.reloadAfterRemoteChange()
        #expect(engine.workout == nil)
    }

    @Test func workoutFinishedElsewhereIsDroppedAndRunningOneIsKept() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let running = try engine.startEmpty()

        // Still running: kept as is.
        try engine.reloadAfterRemoteChange()
        #expect(engine.workout === running)

        try mutateElsewhere(rig) { remote, _ in remote.finishedAt = rig.clock.date }
        try engine.reloadAfterRemoteChange()
        #expect(engine.workout == nil)
    }

    @Test func newerWorkoutStartedElsewhereDoesNotReplaceTheRunningOne() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let running = try engine.startEmpty()
        rig.clock.advance(300)
        let remote = Workout(name: "Elsewhere", startedAt: rig.clock.date)
        remote.updatedAt = rig.clock.date
        let other = ModelContext(rig.container)
        other.insert(remote)
        try other.save()

        try engine.reloadAfterRemoteChange()
        #expect(engine.workout === running)
        let inProgress = try rig.context.fetch(FetchDescriptor<Workout>(predicate: Workout.inProgressPredicate))
        #expect(Set(inProgress.map(\.id)) == [running.id, remote.id])
        #expect(try rig.context.fetchCount(FetchDescriptor<Workout>()) == 2)
    }

    @Test func workoutStartedElsewhereAppearsAfterRemoteChange() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        #expect(engine.workout == nil)
        let remote = Workout(name: "Elsewhere", startedAt: rig.clock.date)
        let other = ModelContext(rig.container)
        other.insert(remote)
        try other.save()

        try engine.reloadAfterRemoteChange()
        #expect(engine.workout?.id == remote.id)
    }

    @Test func expiredRestIsClearedEvenWhenTheSaveFails() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let running = try engine.startEmpty()
        try engine.startRest(seconds: 60)
        #expect(running.restEndsAt != nil)

        rig.clock.advance(120)
        engine.saveHook = { throw SaveFailed() }
        let resumed = try engine.resume()
        #expect(resumed === running)
        #expect(engine.workout === running)
        #expect(running.restEndsAt == nil)

        engine.saveHook = nil
        try engine.startRest(seconds: 30)
        #expect(running.restEndsAt != nil)
    }
}
