import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct RestTimerTests {
    typealias Rig = EngineTests.Rig

    private func sets(_ row: WorkoutExercise) -> [WorkoutSet] {
        (row.sets ?? []).sorted { $0.position < $1.position }
    }

    /// An engine with a running empty workout holding squat (rest 90 s default) and curl (rest 60 s), sets filled
    /// with 50 x 5 so they can be checked. The default is pinned to 90 s here, apart from the app's shipped default, so
    /// the two rests stay distinguishable.
    private func running(_ rig: Rig) throws -> (
        engine: ActiveWorkoutEngine, squat: WorkoutExercise, curl: WorkoutExercise
    ) {
        rig.settings.defaultRestSeconds = 90
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let squat = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let curl = try engine.addExercise(try rig.info(LibraryFixture.curl))
        curl.restSeconds = 60
        for set in sets(squat) + sets(curl) { try engine.setValues(set, weight: 50, reps: 5, durationSeconds: nil) }
        return (engine, squat, curl)
    }

    private func timer(_ clock: EngineTests.Clock, _ state: RestTimer.State = .idle) -> RestTimer {
        RestTimer(state: state, now: { clock.date })
    }

    // MARK: Value

    @Test func startSetsEndAndTotalFromTheClock() throws {
        let clock = EngineTests.Clock()
        let id = UUID()
        var rest = timer(clock)
        #expect(rest.state == .idle && !rest.isActive)
        #expect(rest.endsAt == nil && rest.total == nil && rest.setID == nil)
        try rest.start(seconds: 90, for: id)
        #expect(rest.state == .running(endsAt: clock.date.addingTimeInterval(90), total: 90, setID: id))
        #expect(rest.isActive && rest.total == 90 && rest.setID == id)
        #expect(rest.endsAt == clock.date.addingTimeInterval(90))
        #expect(throws: RestTimerError.invalidDuration(0)) { try rest.start(seconds: 0) }
        #expect(throws: RestTimerError.invalidDuration(3601)) { try rest.start(seconds: 3601) }
        #expect(rest.total == 90)
        try rest.start(seconds: 3600)
        #expect(rest.total == 3600 && rest.setID == nil)
    }

    @Test func remainingAndExpiryDeriveFromTheDate() throws {
        let clock = EngineTests.Clock()
        var rest = timer(clock)
        #expect(rest.remaining(at: clock.date) == 0)
        #expect(!rest.isExpired(at: clock.date.addingTimeInterval(999)))
        try rest.start(seconds: 60)
        #expect(rest.remaining(at: clock.date) == 60)
        #expect(rest.remaining(at: clock.date.addingTimeInterval(45)) == 15)
        #expect(!rest.isExpired(at: clock.date.addingTimeInterval(59.9)))
        #expect(rest.isExpired(at: clock.date.addingTimeInterval(60)))
        #expect(rest.remaining(at: clock.date.addingTimeInterval(500)) == 0)
    }

    @Test func adjustMovesEndAndTotalTogether() throws {
        let clock = EngineTests.Clock()
        var rest = timer(clock)
        try rest.adjust(by: 30)  // idle: no-op
        #expect(rest.state == .idle)
        try rest.start(seconds: 60)
        clock.advance(20)
        try rest.adjust(by: 30)
        #expect(rest.total == 90 && rest.remaining(at: clock.date) == 70)
        try rest.adjust(by: 10)
        #expect(rest.total == 100 && rest.remaining(at: clock.date) == 80)
        try rest.adjust(by: -10)
        #expect(rest.total == 90 && rest.remaining(at: clock.date) == 70)
    }

    @Test func adjustRejectsOtherAmountsAndNeverGoesBelowNow() throws {
        let clock = EngineTests.Clock()
        var rest = timer(clock)
        try rest.start(seconds: 60)
        for amount in [0, 5, -30, 15, 60] {
            #expect(throws: RestTimerError.invalidAdjustment(amount)) { try rest.adjust(by: amount) }
        }
        #expect(rest.total == 60)
        // -10 with exactly 10 s left, and with less, ends the rest.
        clock.advance(50)
        try rest.adjust(by: -10)
        #expect(rest.state == .idle)
        try rest.start(seconds: 60)
        clock.advance(55)
        try rest.adjust(by: -10)
        #expect(rest.state == .idle)
    }

    @Test func adjustOnAnOverRestRestartsFromNow() throws {
        let clock = EngineTests.Clock()
        let id = UUID()
        var rest = timer(clock)
        try rest.start(seconds: 30, for: id)
        clock.advance(31)
        try rest.adjust(by: 10)
        #expect(rest.state == .running(endsAt: clock.date.addingTimeInterval(10), total: 10, setID: id))
        clock.advance(11)
        try rest.adjust(by: -10)
        #expect(rest.state == .idle)
    }

    @Test func skipAndTickClear() throws {
        let clock = EngineTests.Clock()
        var rest = timer(clock)
        try rest.start(seconds: 30)
        rest.skip()
        #expect(rest.state == .idle)
        try rest.start(seconds: 30)
        clock.advance(30)
        var cleared = rest.tick()
        #expect(!cleared)  // over, but inside the 3 s grace
        #expect(rest.isActive)
        clock.advance(2.9)
        cleared = rest.tick()
        #expect(!cleared)
        clock.advance(0.1)
        cleared = rest.tick()
        #expect(cleared && rest.state == .idle)
        cleared = rest.tick()
        #expect(!cleared)
    }

    @Test func clearIfExpiredDropsOnlyOverRests() throws {
        let clock = EngineTests.Clock()
        var rest = timer(clock)
        var cleared = rest.clearIfExpired()
        #expect(!cleared)
        try rest.start(seconds: 30)
        clock.advance(29)
        cleared = rest.clearIfExpired()
        #expect(!cleared)
        clock.advance(1)
        cleared = rest.clearIfExpired()
        #expect(cleared && rest.state == .idle)
    }

    @Test func writeAndReadRoundTripThroughTheWorkout() throws {
        let clock = EngineTests.Clock()
        let workout = Workout()
        var rest = timer(clock)
        try rest.start(seconds: 45, for: workout.id)
        rest.write(to: workout)
        #expect(workout.restEndsAt == clock.date.addingTimeInterval(45))
        #expect(workout.restSeconds == 45 && workout.restSetID == workout.id)
        #expect(RestTimer(workout: workout, now: { clock.date }).state == rest.state)
        rest.skip()
        rest.write(to: workout)
        #expect(workout.restEndsAt == nil && workout.restSeconds == nil && workout.restSetID == nil)
        #expect(RestTimer(workout: workout).state == .idle)
        // A half-written workout reads as idle.
        workout.restSeconds = 30
        #expect(RestTimer(workout: workout).state == .idle)
    }

    // MARK: Presets

    @Test func recordingInsertsNewestFirstWithoutRepeats() {
        #expect(RestTimer.defaultPresets == [30, 60, 120, 180])
        #expect(RestTimer.recording(45, in: []) == [45])
        #expect(RestTimer.recording(75, in: [45]) == [75, 45])
        #expect(RestTimer.recording(45, in: [75, 45, 100]) == [45, 75, 100])
    }

    @Test func recordingSkipsDefaultsAndOutOfRangeValues() {
        for seconds in [30, 60, 120, 180, 0, -5, 3601] {
            #expect(RestTimer.recording(seconds, in: [45, 75]) == [45, 75])
        }
        #expect(RestTimer.recording(1, in: []) == [1])
        #expect(RestTimer.recording(3600, in: []) == [3600])
    }

    @Test func recordingCapsAtSixDroppingTheOldest() {
        let full = [11, 12, 13, 14, 15, 16]
        #expect(RestTimer.recording(17, in: full) == [17, 11, 12, 13, 14, 15])
        #expect(RestTimer.recording(16, in: full) == [16, 11, 12, 13, 14, 15])
    }

    // MARK: Engine

    @Test func checkStartsTheRowsRestForThatSet() throws {
        let rig = try Rig()
        let (engine, squat, curl) = try running(rig)
        #expect(engine.restTimer.state == .idle)
        let first = sets(squat)[0]
        try engine.check(first)
        let workout = try #require(engine.workout)
        #expect(workout.restEndsAt == rig.clock.date.addingTimeInterval(90))
        #expect(workout.restSeconds == 90 && workout.restSetID == first.id)
        #expect(engine.restTimer.remaining(at: rig.clock.date) == 90)

        // The exercise's own rest wins over the default; a check replaces the running rest.
        rig.clock.advance(10)
        let curlSet = sets(curl)[0]
        try engine.check(curlSet)
        #expect(workout.restSeconds == 60 && workout.restSetID == curlSet.id)
        #expect(engine.restTimer.remaining(at: rig.clock.date) == 60)
    }

    @Test func everyCheckInASupersetRestartsTheRest() throws {
        let rig = try Rig()
        let (engine, squat, curl) = try running(rig)
        squat.supersetGroup = 1
        curl.supersetGroup = 1
        let a = sets(squat)[0]
        let b = sets(curl)[0]
        try engine.check(a)
        rig.clock.advance(20)
        try engine.check(b)
        #expect(engine.restTimer.setID == b.id)
        #expect(engine.restTimer.endsAt == rig.clock.date.addingTimeInterval(60))
        rig.clock.advance(5)
        try engine.check(sets(squat)[1])
        #expect(engine.restTimer.endsAt == rig.clock.date.addingTimeInterval(90))
    }

    @Test func restOffStartsNothingAndLeavesARunningRest() throws {
        let rig = try Rig()
        let (engine, squat, curl) = try running(rig)
        curl.restSeconds = 0
        try engine.check(sets(squat)[0])
        let before = engine.restTimer.state
        try engine.check(sets(curl)[0])
        #expect(engine.restTimer.state == before)
        // Off with nothing running starts nothing.
        try engine.skipRest()
        try engine.check(sets(curl)[1])
        #expect(engine.restTimer.state == .idle)
        // A rest longer than the cap is clamped to 3600.
        squat.restSeconds = 9000
        try engine.check(sets(squat)[1])
        #expect(engine.restTimer.total == 3600)
    }

    @Test func checkWithRestZeroStartsNoRestAndNilStartsTheDefault() throws {
        let rig = try Rig()
        let (engine, squat, curl) = try running(rig)
        #expect(squat.restSeconds == nil)
        squat.restSeconds = 0
        try engine.check(sets(squat)[0])
        #expect(engine.restTimer.state == .idle)  // Off: no timer
        squat.restSeconds = nil
        try engine.check(sets(squat)[1])
        #expect(engine.restTimer.total == 90)  // Default: the Settings rest
        _ = curl
    }

    @Test func defaultRestFollowsASettingsChangeAfterTheRowWasMade() throws {
        let rig = try Rig()
        let (engine, squat, _) = try running(rig)
        rig.settings.defaultRestSeconds = 150
        try engine.check(sets(squat)[0])
        #expect(engine.restTimer.total == 150)
        rig.settings.defaultRestSeconds = 0  // a default of Off: nothing starts
        try engine.skipRest()
        try engine.check(sets(squat)[1])
        #expect(engine.restTimer.state == .idle)
    }

    @Test func aTemplateRowSetToOffStartsNoRestInTheWorkout() throws {
        let rig = try Rig()
        let template = try rig.pushTemplate()
        let squatRow = try #require((template.exercises ?? []).first { $0.exerciseID == LibraryFixture.squat })
        squatRow.restSeconds = 0
        let engine = try rig.makeEngine()
        let workout = try engine.start(from: template)
        let row = try #require((workout.exercises ?? []).first { $0.exerciseID == LibraryFixture.squat })
        #expect(row.restSeconds == 0)
        let set = try #require(sets(row).first { $0.kind == .normal })
        try engine.setValues(set, weight: 50, reps: 5, durationSeconds: nil)
        try engine.check(set)
        #expect(engine.restTimer.state == .idle)
    }

    @Test func uncheckCancelsOnlyTheRestThatSetStarted() throws {
        let rig = try Rig()
        let (engine, squat, _) = try running(rig)
        let first = sets(squat)[0]
        let second = sets(squat)[1]
        try engine.check(first)
        try engine.check(second)
        // `first` no longer owns the rest.
        try engine.uncheck(first)
        #expect(engine.restTimer.setID == second.id)
        try engine.uncheck(second)
        #expect(engine.restTimer.state == .idle)
        let workout = try #require(engine.workout)
        #expect(workout.restEndsAt == nil && workout.restSeconds == nil && workout.restSetID == nil)
        // A rest started by hand survives an uncheck.
        try engine.check(first)
        try engine.startRest(seconds: 45)
        try engine.uncheck(first)
        #expect(engine.restTimer.total == 45)
    }

    @Test func removingSetsOrExercisesCancelsTheirRestButNotAHandStartedOne() throws {
        let rig = try Rig()
        let (engine, squat, curl) = try running(rig)
        try engine.check(sets(squat)[0])
        try engine.removeSet(sets(squat)[0])
        #expect(engine.restTimer.state == .idle)
        try engine.check(sets(curl)[0])
        try engine.removeExercise(curl)
        #expect(engine.restTimer.state == .idle)
        try engine.startRest(seconds: 45)
        try engine.removeExercise(squat)
        #expect(engine.restTimer.total == 45)
    }

    @Test func startRestByHandBelongsToNoSetAndSavesCustoms() throws {
        let rig = try Rig()
        let (engine, _, _) = try running(rig)
        try engine.startRest(seconds: 120)  // a default: not saved
        #expect(engine.restTimer.total == 120 && engine.restTimer.setID == nil)
        #expect(rig.settings.restPresets.isEmpty)
        try engine.startRest(seconds: 45)
        try engine.startRest(seconds: 75)
        try engine.startRest(seconds: 45)
        #expect(rig.settings.restPresets == [45, 75])
        #expect(throws: RestTimerError.invalidDuration(0)) { try engine.startRest(seconds: 0) }
        #expect(throws: RestTimerError.invalidDuration(3601)) { try engine.startRest(seconds: 3601) }
        #expect(rig.settings.restPresets == [45, 75] && engine.restTimer.total == 45)
        for seconds in [11, 12, 13, 14, 15, 16] { try engine.startRest(seconds: seconds) }
        #expect(rig.settings.restPresets == [16, 15, 14, 13, 12, 11])
    }

    @Test func adjustAndSkipThroughTheEngine() throws {
        let rig = try Rig()
        let (engine, squat, _) = try running(rig)
        try engine.adjustRest(by: 30)  // idle: no-op
        #expect(engine.restTimer.state == .idle)
        try engine.check(sets(squat)[0])
        rig.clock.advance(10)
        try engine.adjustRest(by: 30)
        let workout = try #require(engine.workout)
        #expect(workout.restSeconds == 120)
        #expect(workout.restEndsAt == rig.clock.date.addingTimeInterval(110))
        #expect(throws: RestTimerError.invalidAdjustment(5)) { try engine.adjustRest(by: 5) }
        try engine.skipRest()
        #expect(engine.restTimer.state == .idle && workout.restEndsAt == nil)
        try engine.skipRest()  // already idle
    }

    @Test func tickRestForgetsOverRestsAfterTheGrace() throws {
        let rig = try Rig()
        let (engine, squat, _) = try running(rig)
        #expect(try !engine.tickRest())
        try engine.check(sets(squat)[0])
        rig.clock.advance(91)
        #expect(try !engine.tickRest())
        #expect(engine.restTimer.isExpired(at: rig.clock.date) && engine.restTimer.isActive)
        rig.clock.advance(3)
        #expect(try engine.tickRest())
        #expect(engine.restTimer.state == .idle)
    }

    @Test func relaunchRestoresARunningRest() throws {
        let rig = try Rig()
        let (engine, squat, _) = try running(rig)
        let first = sets(squat)[0]
        try engine.check(first)
        let endsAt = rig.clock.date.addingTimeInterval(90)
        rig.clock.advance(30)
        let relaunched = try rig.makeEngine()
        #expect(relaunched.restTimer.state == .running(endsAt: endsAt, total: 90, setID: first.id))
        #expect(relaunched.restTimer.remaining(at: rig.clock.date) == 60)
        // The restored rest is still owned by its set.
        let restored = try #require(relaunched.workout?.exercises?.first { $0.exerciseID == LibraryFixture.squat })
        try relaunched.uncheck(try #require(sets(restored).first { $0.id == first.id }))
        #expect(relaunched.restTimer.state == .idle)
    }

    @Test func relaunchClearsAnExpiredRestAndPersistsIt() throws {
        let rig = try Rig()
        let (engine, squat, _) = try running(rig)
        try engine.check(sets(squat)[0])
        rig.clock.advance(600)
        let relaunched = try rig.makeEngine()
        #expect(relaunched.restTimer.state == .idle)
        let workout = try #require(relaunched.workout)
        #expect(workout.restEndsAt == nil && workout.restSeconds == nil && workout.restSetID == nil)
        #expect(try rig.makeEngine().restTimer.state == .idle)
    }

    @Test func finishAndDiscardLeaveNoRest() throws {
        let rig = try Rig()
        let (engine, squat, _) = try running(rig)
        try engine.check(sets(squat)[0])
        try engine.finish(unfinished: .discard)
        let finished = try #require(try rig.context.fetch(FetchDescriptor<Workout>()).first)
        #expect(finished.restEndsAt == nil && finished.restSeconds == nil && finished.restSetID == nil)
        #expect(engine.restTimer.state == .idle)
        #expect(throws: ActiveWorkoutError.noActiveWorkout) { try engine.startRest(seconds: 30) }
        #expect(throws: ActiveWorkoutError.noActiveWorkout) { try engine.skipRest() }
        #expect(throws: ActiveWorkoutError.noActiveWorkout) { try engine.adjustRest(by: 10) }
        #expect(throws: ActiveWorkoutError.noActiveWorkout) { try engine.tickRest() }
    }
}
