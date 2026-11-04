import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct RestNotificationTests {
    typealias Rig = EngineTests.Rig

    private func sets(_ row: WorkoutExercise) -> [WorkoutSet] {
        (row.sets ?? []).sorted { $0.position < $1.position }
    }

    private func running(_ rig: Rig) throws -> (engine: ActiveWorkoutEngine, squat: WorkoutExercise) {
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let squat = try engine.addExercise(try rig.info(LibraryFixture.squat))
        for set in sets(squat) { try engine.setValues(set, weight: 27.5, reps: 8, durationSeconds: nil) }
        return (engine, squat)
    }

    // MARK: Nil cases

    @Test func nilWithoutAWorkoutOrState() throws {
        #expect(RestNotificationPlan(state: nil) == nil)
        let rig = try Rig()
        let engine = try rig.makeEngine()
        #expect(engine.restNotificationPlan == nil)
    }

    @Test func nilWhenNoRestRuns() throws {
        let rig = try Rig()
        let (engine, _) = try running(rig)
        #expect(engine.restNotificationPlan == nil)
    }

    // MARK: Copy

    @Test func bodyCarriesTheNextSet() throws {
        let rig = try Rig()
        let (engine, squat) = try running(rig)
        try engine.check(sets(squat)[0])
        let plan = try #require(engine.restNotificationPlan)
        #expect(plan.body == "Rest over · Set 2 · 27.5 lb × 8")
        #expect(plan.title == "Back Squat")
        #expect(plan.identifier == RestNotificationPlan.identifier)
        #expect(plan.categoryIdentifier == RestNotificationPlan.categoryIdentifier)
        #expect(plan.actions.map(\.rawValue) == ["skip", "add30"])
        #expect(plan.actions.map(\.title) == ["Skip", "+30 s"])
    }

    @Test func bodyHasNoNextSetWhenEverySetIsChecked() throws {
        let rig = try Rig()
        let (engine, squat) = try running(rig)
        for set in sets(squat) { try engine.check(set) }
        let plan = try #require(engine.restNotificationPlan)
        #expect(plan.body == "Rest over · All sets done")
        #expect(plan.title == "Workout")
    }

    @Test func manualRestWithoutValuesStillNamesTheSet() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        try engine.addExercise(try rig.info(LibraryFixture.curl))
        try engine.startRest(seconds: 60)
        let plan = try #require(engine.restNotificationPlan)
        #expect(plan.body == "Rest over · Set 1")
        #expect(plan.title == "Zottman Curl")
    }

    // MARK: Fire date

    @Test func fireDateMirrorsTheRestAndFollowsAdjustAndSkip() throws {
        let rig = try Rig()
        let (engine, squat) = try running(rig)
        try engine.check(sets(squat)[0])
        let start = rig.clock.date
        let rest = TimeInterval(rig.settings.defaultRestSeconds)
        #expect(engine.restNotificationPlan?.fireDate == start.addingTimeInterval(rest))

        try engine.adjustRest(by: 30)
        #expect(engine.restNotificationPlan?.fireDate == start.addingTimeInterval(rest + 30))
        try engine.adjustRest(by: -10)
        #expect(engine.restNotificationPlan?.fireDate == start.addingTimeInterval(rest + 20))

        try engine.skipRest()
        #expect(engine.restNotificationPlan == nil)
    }

    @Test func uncheckAndDiscardRemoveThePlan() throws {
        let rig = try Rig()
        let (engine, squat) = try running(rig)
        let first = sets(squat)[0]
        try engine.check(first)
        #expect(engine.restNotificationPlan != nil)
        try engine.uncheck(first)
        #expect(engine.restNotificationPlan == nil)
        try engine.check(first)
        try engine.discard()
        #expect(engine.restNotificationPlan == nil)
    }

    @Test func planSurvivesRelaunch() throws {
        let rig = try Rig()
        let (engine, squat) = try running(rig)
        try engine.check(sets(squat)[0])
        let before = try #require(engine.restNotificationPlan)
        let relaunched = try rig.makeEngine()
        #expect(relaunched.restNotificationPlan == before)
    }
}

extension EngineTests {
    private func startedRest(_ rig: Rig) throws -> (engine: ActiveWorkoutEngine, set: WorkoutSet) {
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let set = try #require((row.sets ?? []).first)
        try engine.setValues(set, weight: 100, reps: 5, durationSeconds: nil)
        try engine.check(set)
        return (engine, set)
    }

    private func expectIdle(_ engine: ActiveWorkoutEngine) {
        #expect(engine.restTimer.state == .idle)
        #expect(engine.activityState == nil)
        #expect(engine.activityStaticInfo == nil)
        #expect(engine.restNotificationPlan == nil)
    }

    @Test func derivedStateIsIdleAfterDiscard() throws {
        let rig = try Rig()
        let (engine, _) = try startedRest(rig)
        #expect(engine.restNotificationPlan != nil)
        try engine.discard()
        expectIdle(engine)
    }

    @Test func derivedStateIsIdleAfterFinish() throws {
        let rig = try Rig()
        let (engine, _) = try startedRest(rig)
        try engine.finish(unfinished: .discard)
        expectIdle(engine)
    }

    @Test func derivedStateIsIdleWhenTheWorkoutIsDeletedUnderTheEngine() throws {
        let rig = try Rig()
        let (engine, _) = try startedRest(rig)
        let workout = try #require(engine.workout)
        rig.context.delete(workout)
        expectIdle(engine)
        try rig.context.save()
        expectIdle(engine)
    }
}
