import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct ActivityStateTests {
    typealias Rig = EngineTests.Rig

    private func sets(_ row: WorkoutExercise) -> [WorkoutSet] {
        (row.sets ?? []).sorted { $0.position < $1.position }
    }

    private func running(_ rig: Rig) throws -> (
        engine: ActiveWorkoutEngine, squat: WorkoutExercise, curl: WorkoutExercise
    ) {
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let squat = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let curl = try engine.addExercise(try rig.info(LibraryFixture.curl))
        for set in sets(squat) + sets(curl) { try engine.setValues(set, weight: 50, reps: 5, durationSeconds: nil) }
        return (engine, squat, curl)
    }

    // MARK: Engine mapping

    @Test func nilWithoutAWorkout() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        #expect(engine.activityState == nil)
        #expect(engine.activityStaticInfo == nil)
        let workout = try engine.startEmpty()
        #expect(engine.activityStaticInfo == WorkoutActivityStaticInfo(workoutID: workout.id))
    }

    @Test func emptyWorkoutHasNoCurrentSet() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let state = try #require(engine.activityState)
        #expect(state.workoutName == "Workout")
        #expect(state.startedAt == rig.clock.date)
        #expect(state.current == nil)
        #expect(state.setsDone == 0 && state.setsTotal == 0)
        #expect(!state.isResting)
    }

    @Test func currentSetFollowsTheFirstUncheckedSet() throws {
        let rig = try Rig()
        let (engine, squat, curl) = try running(rig)
        let squatSets = sets(squat)
        var state = try #require(engine.activityState)
        #expect(state.setsDone == 0 && state.setsTotal == 6)
        #expect(state.current?.setID == squatSets[0].id)
        #expect(state.current?.exerciseName == "Back Squat")
        #expect(state.current?.number == 1 && state.current?.count == 3)

        try engine.check(squatSets[0])
        state = try #require(engine.activityState)
        #expect(state.current?.setID == squatSets[1].id)
        #expect(state.current?.progressText == "Set 2 of 3")
        #expect(state.setsDone == 1)

        // Checking out of order moves on from the set just checked; unchecking an earlier set does not pull the
        // activity back (the most recent set is still squatSets[2]).
        rig.clock.advance(10)
        try engine.check(squatSets[2])
        #expect(try #require(engine.activityState).current?.setID == sets(curl)[0].id)
        try engine.uncheck(squatSets[0])
        #expect(try #require(engine.activityState).current?.setID == sets(curl)[0].id)
        rig.clock.advance(10)
        try engine.check(squatSets[0])
        rig.clock.advance(10)
        try engine.check(squatSets[1])

        state = try #require(engine.activityState)
        #expect(state.current?.setID == sets(curl)[0].id)
        #expect(state.current?.exerciseName == "Zottman Curl")
        #expect(state.setsDone == 3)

        for set in sets(curl) { try engine.check(set) }
        state = try #require(engine.activityState)
        #expect(state.current == nil)
        #expect(state.setsDone == 6 && state.setsTotal == 6)
    }

    @Test func skippedSetDoesNotHoldTheActivityBack() throws {
        let rig = try Rig()
        let (engine, squat, curl) = try running(rig)
        let squatSets = sets(squat)
        let curlSets = sets(curl)
        for set in squatSets.prefix(2) {
            rig.clock.advance(10)
            try engine.check(set)
        }
        // Squat set 3 is skipped; the lifter moves on to curls.
        rig.clock.advance(10)
        try engine.check(curlSets[0])
        var current = try #require(engine.activityState?.current)
        #expect(current.setID == curlSets[1].id)
        #expect(current.exerciseName == "Zottman Curl" && current.number == 2)

        // After the last curl set nothing follows, so the skipped squat set comes back.
        rig.clock.advance(10)
        try engine.check(curlSets[1])
        rig.clock.advance(10)
        try engine.check(curlSets[2])
        current = try #require(engine.activityState?.current)
        #expect(current.setID == squatSets[2].id)
        #expect(current.progressText == "Set 3 of 3")

        rig.clock.advance(10)
        try engine.check(squatSets[2])
        #expect(engine.activityState?.current == nil)
    }

    @Test func supersetAlternatesBetweenItsExercises() throws {
        let rig = try Rig()
        let (engine, squat, curl) = try running(rig)
        squat.supersetGroup = 1
        curl.supersetGroup = 1
        #expect(try #require(engine.activityState).current?.setID == sets(squat)[0].id)
        try engine.check(sets(squat)[0])
        #expect(try #require(engine.activityState).current?.setID == sets(curl)[0].id)
        try engine.check(sets(curl)[0])
        #expect(try #require(engine.activityState).current?.setID == sets(squat)[1].id)
        // Reordering changes which exercise leads.
        try engine.reorderExercises([curl, squat])
        #expect(try #require(engine.activityState).current?.setID == sets(curl)[1].id)
    }

    @Test func supersetWithUnequalSetCountsDropsOutTheExhaustedExercise() throws {
        let rig = try Rig()
        let (engine, squat, curl) = try running(rig)
        squat.supersetGroup = 1
        curl.supersetGroup = 1
        try engine.removeSet(sets(curl)[2])
        try engine.removeSet(sets(curl)[1])
        // Order: squat1, curl1, squat2, squat3.
        try engine.check(sets(squat)[0])
        try engine.check(sets(curl)[0])
        #expect(try #require(engine.activityState).current?.setID == sets(squat)[1].id)
        try engine.check(sets(squat)[1])
        let current = try #require(engine.activityState).current
        #expect(current?.setID == sets(squat)[2].id && current?.number == 3)
    }

    @Test func setOrderRoundRobinsAdjacentSupersetBlocksOnly() {
        func order(_ groups: [Int?], _ counts: [Int]) -> [String] {
            activitySetOrder(groups: groups, counts: counts).map { "\($0.exercise):\($0.set)" }
        }
        #expect(order([nil, nil], [2, 1]) == ["0:0", "0:1", "1:0"])
        #expect(order([1, 1, 1], [2, 2, 1]) == ["0:0", "1:0", "2:0", "0:1", "1:1"])
        #expect(order([1, 1], [1, 3]) == ["0:0", "1:0", "1:1", "1:2"])
        // A group number reused after a gap is two blocks; a lone member of a group is plain.
        #expect(order([1, nil, 1], [2, 1, 1]) == ["0:0", "0:1", "1:0", "2:0"])
        #expect(order([nil, 2, 2, nil], [1, 2, 1, 1]) == ["0:0", "1:0", "2:0", "1:1", "3:0"])
        #expect(order([1, 1], [0, 2]) == ["1:0", "1:1"])
        #expect(order([], []) == [])
    }

    @Test func valuesAreWhatDoneWouldRecord() throws {
        let rig = try Rig()
        let template = try rig.pushTemplate()
        let engine = try rig.makeEngine()
        try engine.start(from: template)
        // Rows start empty; the plan fills the display: warm-up first, then the normal sets.
        var current = try #require(engine.activityState?.current)
        #expect(current.kind == .warmup && current.unit == .kg)
        #expect(current.weight == 60 && current.reps == 5 && !current.isEmpty)
        #expect(current.nextSetText == "Set 1 (warm-up) · 60 kg × 5")
        let first = try #require(engine.workout?.exercises?.min { $0.position < $1.position })
        try engine.check(sets(first)[0])
        current = try #require(engine.activityState?.current)
        #expect(current.nextSetText == "Set 2 · 100 kg × 5")
        #expect(current.detailText == "100 kg × 5")
    }

    @Test func emptySetIsFlaggedWhenDoneWouldBeRefused() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        try engine.addExercise(try rig.info(LibraryFixture.squat))
        let current = try #require(engine.activityState?.current)
        #expect(current.isEmpty)
        #expect(current.detailText.isEmpty)
        #expect(current.nextSetText == "Set 1")
    }

    @Test func bodyweightAndDurationSetsFormatTheirValues() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let stretch = try engine.addExercise(try rig.info(LibraryFixture.etirement))
        try engine.setValues(sets(stretch)[0], weight: nil, reps: 12, durationSeconds: nil)
        #expect(engine.activityState?.current?.detailText == "12 reps")
        try engine.check(sets(stretch)[0])
        try engine.setValues(sets(stretch)[1], weight: nil, reps: nil, durationSeconds: 45)
        #expect(engine.activityState?.current?.detailText == "0:45")
        #expect(engine.activityState?.current?.nextSetText == "Set 2 · 0:45")
    }

    @Test func restFieldsMirrorTheRestTimer() throws {
        let rig = try Rig()
        let (engine, squat, _) = try running(rig)
        #expect(engine.activityState?.restEndsAt == nil && engine.activityState?.restTotal == nil)
        try engine.check(sets(squat)[0])
        var timer = engine.restTimer
        var state = try #require(engine.activityState)
        #expect(state.isResting)
        #expect(state.restEndsAt == timer.endsAt && state.restEndsAt != nil)
        #expect(state.restTotal == timer.total)

        try engine.adjustRest(by: 30)
        timer = engine.restTimer
        state = try #require(engine.activityState)
        #expect(state.restEndsAt == timer.endsAt && state.restTotal == timer.total)

        try engine.startRest(seconds: 60)
        state = try #require(engine.activityState)
        #expect(state.restTotal == 60)
        #expect(state.restEndsAt == rig.clock.date.addingTimeInterval(60))

        try engine.skipRest()
        state = try #require(engine.activityState)
        #expect(state.restEndsAt == nil && state.restTotal == nil && !state.isResting)
    }

    @Test func longNamesAreShortened() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let workout = try engine.startEmpty()
        workout.name = String(repeating: "W", count: 300)
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        row.exerciseName = String(repeating: "E", count: 300)
        let state = try #require(engine.activityState)
        #expect(state.workoutName.count == WorkoutActivityState.maxNameLength)
        #expect(state.current?.exerciseName.count == WorkoutActivityState.maxNameLength)
        #expect(state.workoutName.hasSuffix("…"))
    }

    // MARK: Codable and size

    @Test func stateRoundTripsThroughJSON() throws {
        let state = WorkoutActivityState(
            workoutName: "Push",
            startedAt: TestSupport.referenceDate,
            restEndsAt: Date(timeIntervalSince1970: 1_800_000_090),
            restTotal: 90,
            setsDone: 4,
            setsTotal: 12,
            current: WorkoutActivitySet(
                setID: UUID(),
                exerciseName: "Bench Press",
                number: 3,
                count: 4,
                kind: .drop,
                weight: 27.5,
                unit: .lb,
                reps: 8,
                durationSeconds: nil,
                isEmpty: false
            )
        )
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(WorkoutActivityState.self, from: data) == state)
        let info = WorkoutActivityStaticInfo(workoutID: UUID())
        let infoData = try JSONEncoder().encode(info)
        #expect(try JSONDecoder().decode(WorkoutActivityStaticInfo.self, from: infoData) == info)
    }

    @Test func encodedStateStaysUnderActivityKitsFourKilobytes() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let workout = try engine.startEmpty()
        workout.name = String(repeating: "Marathon Day ", count: 40) + "🏋️"
        for index in 0..<40 {
            let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
            row.exerciseName = String(repeating: "Dumbbell Romanian Deadlift 🏋️ \(index) ", count: 12)
            for set in sets(row) { try engine.setValues(set, weight: 1234.56, reps: 99, durationSeconds: 3599) }
        }
        try engine.startRest(seconds: 3600)
        let state = try #require(engine.activityState)
        #expect(state.setsTotal == 120 && state.current != nil && state.isResting)
        let size = try JSONEncoder().encode(state).count
        #expect(size < 4096)
        // Names are capped, so the size is a few hundred bytes, far from the limit.
        #expect(size < 1024)
    }

    // MARK: Formatting

    @Test func formatSetDetailCoversLoadsRepsAndDurations() {
        #expect(formatSetDetail(weight: 27.5, unit: .lb, reps: 8, durationSeconds: nil) == "27.5 lb × 8")
        #expect(formatSetDetail(weight: 100, unit: .kg, reps: 5, durationSeconds: nil) == "100 kg × 5")
        #expect(formatSetDetail(weight: nil, unit: .kg, reps: 12, durationSeconds: nil) == "12 reps")
        #expect(formatSetDetail(weight: 0, unit: .lb, reps: 12, durationSeconds: nil) == "12 reps")
        #expect(formatSetDetail(weight: nil, unit: .lb, reps: nil, durationSeconds: 45) == "0:45")
        #expect(formatSetDetail(weight: 20, unit: .lb, reps: nil, durationSeconds: 90) == "20 lb × 1:30")
        #expect(formatSetDetail(weight: 27.5, unit: .lb, reps: nil, durationSeconds: nil) == "27.5 lb")
        #expect(formatSetDetail(weight: nil, unit: .lb, reps: 0, durationSeconds: 0) == "")
        #expect(formatSetDetail(weight: nil, unit: .lb, reps: nil, durationSeconds: nil) == "")
    }

    @Test func formatKindNamesEachKind() {
        #expect(formatKind(.warmup) == "warm-up")
        #expect(formatKind(.normal) == "normal")
        #expect(formatKind(.drop) == "drop")
        #expect(formatKind(.failure) == "failure")
    }

    @Test func shortenedNameKeepsShortNamesAndEllipsizesLongOnes() {
        #expect(shortenedName("Squat", limit: 10) == "Squat")
        #expect(shortenedName("1234567890", limit: 10) == "1234567890")
        #expect(shortenedName("12345678901", limit: 10) == "123456789…")
        #expect(shortenedName("abc", limit: 0) == "abc")
    }

    @Test func notificationAndProgressCopy() {
        let set = WorkoutActivitySet(
            setID: UUID(),
            exerciseName: "Bench Press",
            number: 3,
            count: 4,
            weight: 27.5,
            unit: .lb,
            reps: 8
        )
        #expect(set.nextSetText == "Set 3 · 27.5 lb × 8")
        #expect(set.progressText == "Set 3 of 4")
        var failure = set
        failure.kind = .failure
        #expect(failure.nextSetText == "Set 3 (failure) · 27.5 lb × 8")
    }
}

@Suite struct ActivityRestOverTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func restOverOnlyWhenARestEndedAtOrBeforeTheDate() {
        let none = WorkoutActivityState(workoutName: "Push", startedAt: now)
        #expect(!none.isRestOver(at: now))
        var state = none
        state.restEndsAt = now.addingTimeInterval(30)
        #expect(!state.isRestOver(at: now))
        #expect(state.isRestOver(at: now.addingTimeInterval(30)))
        #expect(state.isRestOver(at: now.addingTimeInterval(31)))
    }
}
