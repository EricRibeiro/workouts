import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct EngineTests {
    final class Clock {
        var date = TestSupport.referenceDate
        func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
    }

    /// One in-memory store plus everything an engine needs; `makeEngine()` is a fresh "app launch" on the same store.
    struct Rig {
        let container: ModelContainer
        let store: ExerciseStore
        let settings: SettingsStore
        let clock = Clock()
        var context: ModelContext { container.mainContext }

        init(custom: [Exercise] = []) throws {
            container = try makeTestContainer()
            store = ExerciseStore(catalog: try LibraryFixture.catalog(), custom: custom)
            settings = SettingsStore(backend: InMemoryBackend())
        }

        func makeEngine() throws -> ActiveWorkoutEngine {
            let clock = clock
            return try ActiveWorkoutEngine(context: context, store: store, settings: settings, now: { clock.date })
        }

        func info(_ id: UUID) throws -> ExerciseInfo {
            try #require(store.exercise(id: id))
        }

        /// A finished workout with one exercise whose sets are all completed.
        @discardableResult
        func finishedWorkout(
            exercise: UUID,
            unit: WeightUnit,
            sets: [(weight: Double?, reps: Int?, kind: SetKind)],
            startedAt: Date
        ) -> Workout {
            let workout = Workout(name: "Past", startedAt: startedAt, finishedAt: startedAt.addingTimeInterval(3600))
            context.insert(workout)
            let row = WorkoutExercise(exerciseID: exercise, exerciseName: "Past", unit: unit)
            context.insert(row)
            row.workout = workout
            for (position, value) in sets.enumerated() {
                let set = WorkoutSet(
                    position: position,
                    kind: value.kind,
                    weight: value.weight,
                    reps: value.reps,
                    completed: true,
                    completedAt: startedAt
                )
                context.insert(set)
                set.workoutExercise = row
            }
            return workout
        }

        /// Push: squat (warm-up 60x5 plus 100x5, 100x5 kg) and curl (one set 12.5x10).
        func pushTemplate() throws -> Template {
            let template = Template(name: "Push")
            context.insert(template)
            func add(
                _ id: UUID,
                position: Int,
                unit: WeightUnit,
                group: Int?,
                rest: Int?,
                sets: [(SetKind, Double?, Int?)]
            ) {
                let row = TemplateExercise(
                    exerciseID: id,
                    exerciseName: id == LibraryFixture.squat ? "Back Squat" : "Zottman Curl",
                    position: position,
                    supersetGroup: group,
                    note: "tempo",
                    restSeconds: rest,
                    unit: unit
                )
                context.insert(row)
                row.template = template
                for (index, value) in sets.enumerated() {
                    let set = TemplateSet(position: index, kind: value.0, weight: value.1, reps: value.2)
                    context.insert(set)
                    set.templateExercise = row
                }
            }
            add(
                LibraryFixture.squat,
                position: 0,
                unit: .kg,
                group: nil,
                rest: 150,
                sets: [(.warmup, 60, 5), (.normal, 100, 5), (.normal, 100, 5)]
            )
            add(LibraryFixture.curl, position: 1, unit: .kg, group: nil, rest: nil, sets: [(.normal, 12.5, 10)])
            try context.save()
            return template
        }
    }

    private func rows(_ workout: Workout) -> [WorkoutExercise] {
        (workout.exercises ?? []).sorted { $0.position < $1.position }
    }

    private func sets(_ row: WorkoutExercise) -> [WorkoutSet] {
        (row.sets ?? []).sorted { $0.position < $1.position }
    }

    // MARK: Start, resume

    @Test func startEmptyCreatesAnEmptyWorkoutNamedWorkout() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let workout = try engine.startEmpty()
        #expect(workout.name == "Workout")
        #expect(workout.finishedAt == nil)
        #expect(workout.startedAt == rig.clock.date)
        #expect((workout.exercises ?? []).isEmpty)
        #expect(engine.workout === workout)
        #expect(try rig.context.fetchCount(FetchDescriptor<Workout>()) == 1)
    }

    @Test func startFromTemplateCopiesExercisesAndSetsInOrder() throws {
        let rig = try Rig()
        let template = try rig.pushTemplate()
        let engine = try rig.makeEngine()
        let workout = try engine.start(from: template)
        #expect(workout.name == "Push")
        #expect(workout.template === template)
        let copied = rows(workout)
        #expect(copied.map(\.exerciseID) == [LibraryFixture.squat, LibraryFixture.curl])
        #expect(copied.map(\.exerciseName) == ["Back Squat", "Zottman Curl"])
        #expect(copied.map(\.position) == [0, 1])
        #expect(copied.allSatisfy { $0.unit == .kg && $0.note == "tempo" })
        // The template's own rest is kept; a nil rest stays nil (Default: read from Settings at each check).
        #expect(copied.map(\.restSeconds) == [150, nil])
        let squatSets = sets(copied[0])
        #expect(squatSets.map(\.kind) == [.warmup, .normal, .normal])
        #expect(squatSets.map(\.position) == [0, 1, 2])
        // New ids, sets empty and unchecked; the template values are plans.
        let templateIDs = Set((template.exercises ?? []).map(\.id))
        #expect(copied.allSatisfy { !templateIDs.contains($0.id) })
        #expect(squatSets.allSatisfy { $0.weight == nil && $0.reps == nil && !$0.completed })
        #expect(engine.plan(for: squatSets[1]) == SetPlan(weight: 100, reps: 5))
        #expect(engine.plan(for: sets(copied[1])[0]) == SetPlan(weight: 12.5, reps: 10))
        #expect((template.exercises ?? []).count == 2)
    }

    @Test func planConvertsTemplateWeightToTheRowsCurrentUnit() throws {
        let rig = try Rig()
        let template = Template(name: "Lb")
        rig.context.insert(template)
        let source = TemplateExercise(
            exerciseID: LibraryFixture.squat,
            exerciseName: "Back Squat",
            position: 0,
            unit: .lb
        )
        rig.context.insert(source)
        source.template = template
        let planned = TemplateSet(position: 0, kind: .normal, weight: 100, reps: 5)
        rig.context.insert(planned)
        planned.templateExercise = source
        try rig.context.save()
        let engine = try rig.makeEngine()
        let workout = try engine.start(from: template)
        let row = rows(workout)[0]
        let set = sets(row)[0]
        #expect(engine.plan(for: set)?.weight == 100)
        try engine.setUnit(.kg, for: row)
        #expect(engine.plan(for: set)?.weight == 45.5)  // 100 lb = 45.36 kg -> 45.5
        try engine.check(set)
        #expect(set.weight == 45.5)
        #expect(set.reps == 5)
    }

    @Test func planPairsRepeatedExerciseRowsByOccurrence() throws {
        let rig = try Rig()
        let template = Template(name: "Two squats")
        rig.context.insert(template)
        for (position, weight) in [100.0, 40.0].enumerated() {
            let source = TemplateExercise(
                exerciseID: LibraryFixture.squat,
                exerciseName: "Back Squat",
                position: position,
                unit: .kg
            )
            rig.context.insert(source)
            source.template = template
            let planned = TemplateSet(position: 0, kind: .normal, weight: weight, reps: 5)
            rig.context.insert(planned)
            planned.templateExercise = source
        }
        try rig.context.save()
        let engine = try rig.makeEngine()
        let workout = try engine.start(from: template)
        let squats = rows(workout)
        #expect(engine.plan(for: sets(squats[0])[0]) == SetPlan(weight: 100, reps: 5))
        #expect(engine.plan(for: sets(squats[1])[0]) == SetPlan(weight: 40, reps: 5))
        // A third squat added later has no counterpart in the template.
        let extra = try engine.addExercise(try rig.info(LibraryFixture.squat))
        #expect(engine.plan(for: sets(extra)[0]) == nil)
    }

    @Test func secondStartIsRefused() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        #expect(throws: ActiveWorkoutError.workoutInProgress(name: "Workout")) { try engine.startEmpty() }
        let template = try rig.pushTemplate()
        #expect(throws: ActiveWorkoutError.workoutInProgress(name: "Workout")) { try engine.start(from: template) }
        // Another engine on the same store is refused too.
        let other = try rig.makeEngine()
        #expect(throws: ActiveWorkoutError.workoutInProgress(name: "Workout")) { try other.startEmpty() }
        #expect(try rig.context.fetchCount(FetchDescriptor<Workout>()) == 1)
    }

    @Test func relaunchResumesTheInProgressWorkout() throws {
        let rig = try Rig()
        rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(90, 5, .normal), (100, 5, .normal)],
            startedAt: rig.clock.date.addingTimeInterval(-86_400)
        )
        let first = try rig.makeEngine()
        let workout = try first.start(from: try rig.pushTemplate())
        let firstRow = try #require(rows(workout).first)
        let set = try #require(sets(firstRow).dropFirst().first)
        try first.setValues(set, weight: 102.5, reps: 5, durationSeconds: nil)
        try first.check(set)

        let relaunched = try rig.makeEngine()
        let resumed = try #require(relaunched.workout)
        #expect(resumed.id == workout.id)
        let resumedRow = try #require(rows(resumed).first)
        let resumedSet = try #require(sets(resumedRow).dropFirst().first)
        #expect(resumedSet.completed && resumedSet.weight == 102.5)
        // Previous is loaded again on resume.
        // The template's first working set (index 1, after the warm-up) takes the first working set's Previous.
        #expect(relaunched.previous(for: resumedSet)?.weight == 90)
        // `resume()` is also callable directly and returns the same workout.
        #expect(try relaunched.resume()?.id == workout.id)

        let fresh = try Rig()
        #expect(try fresh.makeEngine().workout == nil)
    }

    // MARK: Check and uncheck

    @Test func checkAndUncheck() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let set = try #require(sets(row).first)
        try engine.setValues(set, weight: 80, reps: 8, durationSeconds: nil)
        rig.clock.advance(60)
        try engine.check(set)
        #expect(set.completed)
        #expect(set.completedAt == rig.clock.date)
        rig.clock.advance(30)
        try engine.uncheck(set)
        #expect(!set.completed && set.completedAt == nil)
        #expect(set.weight == 80 && set.reps == 8)
        // Unchecking an unchecked set is a no-op.
        try engine.uncheck(set)
        #expect(!set.completed)
    }

    @Test func emptySetCannotBeChecked() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let set = try #require(sets(row).first)
        #expect(throws: ActiveWorkoutError.emptySet) { try engine.check(set) }
        #expect(!set.completed && set.completedAt == nil)
        // Zero values are empty too.
        try engine.setValues(set, weight: 0, reps: 0, durationSeconds: nil)
        #expect(throws: ActiveWorkoutError.emptySet) { try engine.check(set) }
    }

    @Test func canCheckMirrorsTheCheckRefusal() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let set = try #require(sets(row).first)
        #expect(!engine.canCheck(set))
        try engine.setValues(set, weight: 0, reps: 0, durationSeconds: nil)
        #expect(!engine.canCheck(set))
        try engine.setValues(set, weight: 70, reps: 8, durationSeconds: nil)
        #expect(engine.canCheck(set))
        try engine.check(set)
        #expect(engine.canCheck(set))
        // Weight alone is not a set for the rep types.
        let stretch = try engine.addExercise(try rig.info(LibraryFixture.etirement))
        let other = try #require(sets(stretch).first)
        try engine.setValues(other, weight: 10, reps: nil, durationSeconds: nil)
        #expect(!engine.canCheck(other))
    }

    @Test func canCheckCountsAutofillFromPrevious() throws {
        let rig = try Rig()
        rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(90, 6, .normal)],
            startedAt: rig.clock.date.addingTimeInterval(-86_400)
        )
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let set = try #require(sets(row).first)
        #expect(engine.canCheck(set))
    }

    @Test func weightAloneDoesNotCountForRepTypes() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.etirement))
        let set = try #require(sets(row).first)
        try engine.setValues(set, weight: 10, reps: nil, durationSeconds: nil)
        #expect(throws: ActiveWorkoutError.emptySet) { try engine.check(set) }
        try engine.setValues(set, weight: nil, reps: nil, durationSeconds: 45)
        try engine.check(set)
        #expect(set.completed)
    }

    @Test func checkFillsEmptyFieldsFromPreviousThenPlan() throws {
        let rig = try Rig()
        rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(90, 6, .normal)],
            startedAt: rig.clock.date.addingTimeInterval(-86_400)
        )
        let engine = try rig.makeEngine()
        let workout = try engine.start(from: try rig.pushTemplate())
        let squat = sets(rows(workout)[0])
        // The first working set (after the warm-up) has a Previous (90 x 6); it wins over the plan (100 x 5). The typed
        // reps stay.
        try engine.setValues(squat[1], weight: nil, reps: 8, durationSeconds: nil)
        try engine.check(squat[1])
        #expect(squat[1].weight == 90 && squat[1].reps == 8)
        // The warm-up has no Previous (it had no warm-up): the plan (60 x 5) fills it. So does the second working set.
        try engine.check(squat[0])
        #expect(squat[0].weight == 60 && squat[0].reps == 5)
        try engine.check(squat[2])
        #expect(squat[2].weight == 100 && squat[2].reps == 5)
    }

    @Test func isTimedFollowsDurationsPreviousAndPlanAndStaysOnce() throws {
        let rig = try Rig()
        let template = Template(name: "Core")
        rig.context.insert(template)
        let planned = TemplateExercise(
            exerciseID: LibraryFixture.squat,
            exerciseName: "Plank",
            position: 0,
            supersetGroup: nil,
            note: "",
            restSeconds: nil,
            unit: .kg
        )
        rig.context.insert(planned)
        planned.template = template
        let plannedSet = TemplateSet(position: 0, kind: .normal, weight: nil, reps: nil, durationSeconds: 60)
        rig.context.insert(plannedSet)
        plannedSet.templateExercise = planned
        let repsRow = TemplateExercise(
            exerciseID: LibraryFixture.curl,
            exerciseName: "Curl",
            position: 1,
            supersetGroup: nil,
            note: "",
            restSeconds: nil,
            unit: .kg
        )
        rig.context.insert(repsRow)
        repsRow.template = template
        let repsSet = TemplateSet(position: 0, kind: .normal, weight: 10, reps: 10)
        rig.context.insert(repsSet)
        repsSet.templateExercise = repsRow
        try rig.context.save()

        let engine = try rig.makeEngine()
        let workout = try engine.start(from: template)
        let plank = rows(workout)[0]
        let curl = rows(workout)[1]
        // The plan alone makes the first row timed; the second stays reps.
        #expect(engine.isTimed(plank))
        #expect(!engine.isTimed(curl))
        // Clearing the only duration (after one was typed) does not flip the row back.
        let set = sets(plank)[0]
        try engine.setValues(set, weight: nil, reps: nil, durationSeconds: 45)
        try engine.setValues(set, weight: nil, reps: nil, durationSeconds: nil)
        #expect(engine.isTimed(plank))
        // A duration typed into a reps row with no plan or Previous duration makes it timed for good.
        let curlSet = sets(curl)[0]
        try engine.setValues(curlSet, weight: nil, reps: nil, durationSeconds: 30)
        #expect(engine.isTimed(curl))
        try engine.setValues(curlSet, weight: nil, reps: nil, durationSeconds: nil)
        #expect(engine.isTimed(curl))
    }

    // MARK: Previous

    @Test func previousIsTheSameKindAndIndexOfTheMostRecentFinishedWorkout() throws {
        let rig = try Rig()
        rig.settings.defaultUnit = .kg
        let day = rig.clock.date
        rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(50, 5, .normal)],
            startedAt: day.addingTimeInterval(-3 * 86_400)
        )
        // Newest finished workout of the exercise, with a warm-up first: indices count the completed sets in order.
        rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(40, 10, .warmup), (100, 5, .normal), (105, 4, .normal)],
            startedAt: day.addingTimeInterval(-86_400)
        )
        // A newer workout with no completed set of it never hides the older real one.
        let planned = rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(200, 1, .normal)],
            startedAt: day.addingTimeInterval(-3600)
        )
        for set in planned.exercises?.first?.sets ?? [] { set.completed = false }
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let rowSets = sets(row)
        // Matched by kind: the row's working sets take the working sets (100, 105) and a warm-up takes the warm-up.
        #expect(engine.previous(for: rowSets[0]) == PreviousSet(kind: .normal, weight: 100, reps: 5))
        #expect(engine.previous(for: rowSets[1]) == PreviousSet(kind: .normal, weight: 105, reps: 4))
        #expect(engine.previous(for: rowSets[2]) == nil)
        try engine.setKind(rowSets[2], to: .warmup)
        #expect(engine.previous(for: rowSets[2]) == PreviousSet(kind: .warmup, weight: 40, reps: 10))
        // A fourth set has no Previous.
        let fourth = try engine.addSet(to: row)
        #expect(engine.previous(for: fourth) == nil)
    }

    @Test func previousIgnoresTheInProgressWorkout() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let first = try engine.addExercise(try rig.info(LibraryFixture.squat))
        try engine.setValues(sets(first)[0], weight: 100, reps: 5, durationSeconds: nil)
        try engine.check(sets(first)[0])
        let second = try engine.addExercise(try rig.info(LibraryFixture.squat))
        #expect(engine.previous(for: sets(second)[0]) == nil)
    }

    @Test func previousIsNeverTakenFromAnUnfinishedWorkout() throws {
        let rig = try Rig()
        rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .lb,
            sets: [(50, 5, .normal)],
            startedAt: rig.clock.date.addingTimeInterval(-86_400)
        )
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        // The running workout is newer and has a completed squat set; it is not finished, so it is not Previous.
        let first = try engine.addExercise(try rig.info(LibraryFixture.squat))
        try engine.setValues(sets(first)[0], weight: 200, reps: 1, durationSeconds: nil)
        try engine.check(sets(first)[0])
        let second = try engine.addExercise(try rig.info(LibraryFixture.squat))
        #expect(engine.previous(for: sets(second)[0]) == PreviousSet(kind: .normal, weight: 50, reps: 5))
    }

    @Test func previousAndPRsAmongManyFinishedWorkoutsOfWhichFewHaveTheExercise() throws {
        let rig = try Rig()
        rig.settings.defaultUnit = .kg
        let day = rig.clock.date
        // 60 finished workouts of another exercise, interleaved by date with three squat workouts.
        for index in 1...60 {
            rig.finishedWorkout(
                exercise: LibraryFixture.curl,
                unit: .kg,
                sets: [(20, 10, .normal)],
                startedAt: day.addingTimeInterval(-Double(index) * 3600)
            )
        }
        rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(60, 5, .normal)],
            startedAt: day.addingTimeInterval(-50 * 3600 - 1)
        )
        rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(90, 5, .normal), (95, 3, .normal)],
            startedAt: day.addingTimeInterval(-20 * 3600 - 1)
        )
        // The newest squat workout has no completed set: skipped.
        let planned = rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(300, 1, .normal)],
            startedAt: day.addingTimeInterval(-3 * 3600 - 1)
        )
        for set in planned.exercises?.first?.sets ?? [] { set.completed = false }

        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let curl = try engine.addExercise(try rig.info(LibraryFixture.curl))
        let squat = try engine.addExercise(try rig.info(LibraryFixture.squat))
        #expect(engine.previous(for: sets(squat)[0]) == PreviousSet(kind: .normal, weight: 90, reps: 5))
        #expect(engine.previous(for: sets(curl)[0]) == PreviousSet(kind: .normal, weight: 20, reps: 10))
        #expect(engine.previous(for: sets(squat)[1]) == PreviousSet(kind: .normal, weight: 95, reps: 3))

        // The PR history reads the same few rows: 110 beats the 95 best of the earlier squat workouts.
        try engine.setValues(sets(squat)[0], weight: 110, reps: 3, durationSeconds: nil)
        try engine.check(sets(squat)[0])
        rig.clock.advance(600)
        let summary = try engine.finishSummary()
        #expect(summary.workoutNumber == 64)
        #expect(
            summary.prs.first { $0.exerciseID == LibraryFixture.squat }?.records.contains { $0.weight == 110 } == true
        )
    }

    @Test func previousConvertsAcrossUnitsAndRoundsToHalf() throws {
        let rig = try Rig()
        rig.settings.defaultUnit = .lb
        let day = rig.clock.date
        // Squat logged in kg, row in lb: 100 kg / 0.45359237 = 220.46 -> 220.5. Same index 1: 20 kg -> 44.09 -> 44.
        rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(100, 5, .normal), (20, 8, .normal)],
            startedAt: day.addingTimeInterval(-86_400)
        )
        // Curl logged in lb, row in kg: 100 lb x 0.45359237 = 45.36 -> 45.5.
        rig.finishedWorkout(
            exercise: LibraryFixture.curl,
            unit: .lb,
            sets: [(100, 10, .normal)],
            startedAt: day.addingTimeInterval(-86_400)
        )
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let squat = try engine.addExercise(try rig.info(LibraryFixture.squat))
        #expect(squat.unit == .lb)
        #expect(engine.previous(for: sets(squat)[0])?.weight == 220.5)
        #expect(engine.previous(for: sets(squat)[1])?.weight == 44)
        #expect(engine.previous(for: sets(squat)[0])?.reps == 5)

        let curl = try engine.addExercise(try rig.info(LibraryFixture.curl))
        curl.unit = .kg
        #expect(engine.previous(for: sets(curl)[0])?.weight == 45.5)
        // Same unit: untouched, no rounding.
        curl.unit = .lb
        #expect(engine.previous(for: sets(curl)[0])?.weight == 100)
    }

    @Test func applyPreviousCopiesIntoTheRow() throws {
        let rig = try Rig()
        rig.settings.defaultUnit = .kg
        rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(90, 6, .normal)],
            startedAt: rig.clock.date.addingTimeInterval(-86_400)
        )
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let rowSets = sets(row)
        try engine.setValues(rowSets[0], weight: 20, reps: 20, durationSeconds: nil)
        #expect(try engine.applyPrevious(to: rowSets[0]))
        #expect(rowSets[0].weight == 90 && rowSets[0].reps == 6 && !rowSets[0].completed)
        // No Previous at index 1: nothing changes.
        #expect(try !engine.applyPrevious(to: rowSets[1]))
        #expect(rowSets[1].weight == nil)
    }

    // MARK: Sets

    @Test func addSetCopiesTheLastSetAndRemoveSetRenumbers() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        try engine.setKind(sets(row)[2], to: .warmup)
        try engine.setValues(sets(row)[2], weight: 40, reps: 10, durationSeconds: nil)
        let added = try engine.addSet(to: row)
        #expect(sets(row).count == 4 && added.position == 3)
        #expect(added.weight == 40 && added.reps == 10)
        #expect(added.kind == .normal)  // a warm-up copy becomes a working set
        #expect(!added.completed)
        try engine.removeSet(sets(row)[1])
        #expect(sets(row).map(\.position) == [0, 1, 2])
        #expect(sets(row).count == 3 && sets(row).last === added)
        // Removing everything and adding again gives an empty normal set.
        for set in sets(row) { try engine.removeSet(set) }
        let fresh = try engine.addSet(to: row)
        #expect(fresh.position == 0 && fresh.weight == nil && fresh.kind == .normal)
    }

    @Test func setValuesClampsAndSetKindChanges() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let set = try #require(sets(row).first)
        try engine.setValues(set, weight: 17.256, reps: -3, durationSeconds: -1)
        #expect(set.weight == 17.26 && set.reps == 0 && set.durationSeconds == 0)
        try engine.setValues(set, weight: -5, reps: nil, durationSeconds: nil)
        #expect(set.weight == 0 && set.reps == nil)
        try engine.setKind(set, to: .failure)
        #expect(set.kind == .failure)
    }

    // MARK: Exercises

    @Test func addExerciseUsesSettingsAndCustomDefaults() throws {
        let sled = Exercise(
            name: "Sled Push",
            weightType: .weighted,
            unit: .kg,
            barType: .custom,
            barWeight: 20,
            restSeconds: 45
        )
        let rig = try Rig(custom: [sled])
        rig.settings.defaultUnit = .kg
        rig.settings.defaultRestSeconds = 120
        let engine = try rig.makeEngine()
        try engine.startEmpty()

        let squat = try engine.addExercise(try rig.info(LibraryFixture.squat))
        #expect(squat.exerciseName == "Back Squat" && squat.position == 0)
        #expect(squat.unit == .kg && squat.barType == .olympic && squat.restSeconds == nil)
        #expect(sets(squat).count == 3 && sets(squat).allSatisfy { $0.weight == nil && !$0.completed })

        let curl = try engine.addExercise(try rig.info(LibraryFixture.curl))
        #expect(curl.barType == BarType.none && curl.position == 1)

        let custom = try engine.addExercise(try rig.info(sled.id))
        #expect(custom.unit == .kg && custom.barType == .custom && custom.barWeight == 20 && custom.restSeconds == 45)

        rig.settings.defaultUnit = .lb
        let multiple = try engine.addExercises([
            try rig.info(LibraryFixture.etirement), try rig.info(LibraryFixture.squat),
        ])
        #expect(multiple.map(\.position) == [3, 4])
        #expect(multiple.allSatisfy { $0.unit == .lb })
        #expect(rows(try #require(engine.workout)).count == 5)
    }

    @Test func replaceExerciseKeepsSetsNoteAndRest() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let workout = try engine.start(from: try rig.pushTemplate())
        let squat = rows(workout)[0]
        let setIDs = sets(squat).map(\.id)
        try engine.replaceExercise(squat, with: try rig.info(LibraryFixture.etirement))
        #expect(squat.exerciseID == LibraryFixture.etirement && squat.exerciseName == "Étirement")
        #expect(sets(squat).map(\.id) == setIDs)
        #expect(squat.note == "tempo" && squat.restSeconds == 150 && squat.position == 0)
    }

    @Test func removeExerciseRenumbersAndDissolvesASuperset() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let a = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let b = try engine.addExercise(try rig.info(LibraryFixture.curl))
        let c = try engine.addExercise(try rig.info(LibraryFixture.etirement))
        a.supersetGroup = 1
        b.supersetGroup = 1
        try engine.removeExercise(a)
        let workout = try #require(engine.workout)
        #expect(rows(workout).map(\.id) == [b.id, c.id])
        #expect(rows(workout).map(\.position) == [0, 1])
        #expect(b.supersetGroup == nil)
        #expect(try rig.context.fetchCount(FetchDescriptor<WorkoutExercise>()) == 2)
        #expect(try rig.context.fetchCount(FetchDescriptor<WorkoutSet>()) == 6)
    }

    @Test func reorderRewritesPositions() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let a = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let b = try engine.addExercise(try rig.info(LibraryFixture.curl))
        let c = try engine.addExercise(try rig.info(LibraryFixture.etirement))
        try engine.reorderExercises([c, a, b])
        #expect(rows(try #require(engine.workout)).map(\.id) == [c.id, a.id, b.id])
        #expect([c, a, b].map(\.position) == [0, 1, 2])
        #expect(throws: ActiveWorkoutError.invalidOrder) { try engine.reorderExercises([a, b]) }
        #expect(throws: ActiveWorkoutError.invalidOrder) { try engine.reorderExercises([a, a, b]) }
    }

    @Test func mutationsStampUpdatedAtAndSave() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let workout = try engine.startEmpty()
        rig.clock.advance(100)
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        #expect(workout.updatedAt == rig.clock.date)
        rig.clock.advance(100)
        try engine.setValues(sets(row)[0], weight: 50, reps: 5, durationSeconds: nil)
        #expect(workout.updatedAt == rig.clock.date && row.updatedAt == rig.clock.date)
        rig.clock.advance(100)
        try engine.rename(to: "Leg day")
        #expect(workout.name == "Leg day" && workout.updatedAt == rig.clock.date)
        #expect(!rig.context.hasChanges)
    }

    @Test func callsWithoutAWorkoutOrForAForeignRowAreRefused() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let stray = WorkoutExercise(exerciseID: LibraryFixture.squat)
        let strayInfo = try rig.info(LibraryFixture.squat)
        #expect(throws: ActiveWorkoutError.noActiveWorkout) { try engine.addExercise(strayInfo) }
        #expect(throws: ActiveWorkoutError.noActiveWorkout) { try engine.finishSummary() }
        #expect(throws: ActiveWorkoutError.noActiveWorkout) { try engine.discard() }
        try engine.startEmpty()
        #expect(throws: ActiveWorkoutError.notInActiveWorkout) { try engine.addSet(to: stray) }
        #expect(throws: ActiveWorkoutError.notInActiveWorkout) { try engine.removeExercise(stray) }
    }

    // MARK: Finish and discard

    /// Squat with a warm-up 60x5 and 105x5 checked, in kg, after a past 100x5 session.
    private func loggedSquat(_ rig: Rig, engine: ActiveWorkoutEngine) throws -> WorkoutExercise {
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        try engine.setKind(sets(row)[0], to: .warmup)
        try engine.setValues(sets(row)[0], weight: 60, reps: 5, durationSeconds: nil)
        try engine.setValues(sets(row)[1], weight: 105, reps: 5, durationSeconds: nil)
        try engine.check(sets(row)[0])
        try engine.check(sets(row)[1])
        return row
    }

    @Test func finishSummaryCountsSetsVolumeAndPRs() throws {
        let rig = try Rig()
        rig.settings.defaultUnit = .kg
        rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(100, 5, .normal)],
            startedAt: rig.clock.date.addingTimeInterval(-86_400)
        )
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try loggedSquat(rig, engine: engine)
        rig.clock.advance(1800)

        let summary = try engine.finishSummary()
        #expect(summary.duration == 1800)
        #expect(summary.setCount == 2 && summary.exerciseCount == 1)
        #expect(summary.volume == 525 && summary.volumeUnit == .kg)  // the warm-up does not count
        #expect(summary.workoutNumber == 2)
        #expect(summary.prCount > 0)
        #expect(summary.prCount == summary.prs.reduce(0) { $0 + $1.records.count })
        #expect(summary.prs.map(\.exerciseID) == [LibraryFixture.squat])
        #expect(summary.prs[0].records.contains { $0.kind == .heaviest && $0.weight == 105 })
        // The third set is unchecked and empty.
        #expect(summary.uncheckedWithValues == 0 && summary.uncheckedWithoutValues == 1)
        #expect(summary.dialog == .unfinishedWithoutValues(count: 1))
        _ = row
    }

    /// Two kg-logged exercises of 11 kg x 1 shown in lb: 24.25 lb each rounds to 24.5 per row (49 summed), but the
    /// 22 kg total is 48.5 lb. The Finish sheet and the History row must show the same, single-rounded figure.
    @Test func finishSheetAndHistoryRowShowTheSameVolume() throws {
        let rig = try Rig()
        rig.settings.defaultUnit = .kg
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        for id in [LibraryFixture.squat, LibraryFixture.curl] {
            let row = try engine.addExercise(try rig.info(id))
            try engine.setValues(sets(row)[0], weight: 11, reps: 1, durationSeconds: nil)
            try engine.check(sets(row)[0])
        }
        rig.settings.defaultUnit = .lb
        rig.clock.advance(600)
        let summary = try engine.finish(unfinished: .discard)

        let workouts = try rig.context.fetch(FetchDescriptor<Workout>())
        let entries = HistoryList.entries(
            from: workouts,
            weightType: { rig.store.exercise(id: $0)?.weightType },
            options: RecordsOptions(displayUnit: .lb)
        )
        #expect(summary.volume == 48.5)
        #expect(entries.first?.volume == summary.volume)
    }

    @Test func finishSummaryWithoutARecordHasNoPRs() throws {
        let rig = try Rig()
        rig.settings.defaultUnit = .kg
        rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(120, 5, .normal)],
            startedAt: rig.clock.date.addingTimeInterval(-86_400)
        )
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        try engine.setValues(sets(row)[0], weight: 100, reps: 5, durationSeconds: nil)
        try engine.check(sets(row)[0])
        let summary = try engine.finishSummary()
        #expect(summary.prCount == 0 && summary.prs.isEmpty)
    }

    @Test func finishSummaryDialogs() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        // Nothing checked, even with typed values.
        try engine.setValues(sets(row)[0], weight: 50, reps: 5, durationSeconds: nil)
        #expect(try engine.finishSummary().dialog == .nothingLogged)
        // One checked, one unchecked with values, one empty.
        try engine.check(sets(row)[0])
        try engine.setValues(sets(row)[1], weight: 50, reps: nil, durationSeconds: nil)
        var summary = try engine.finishSummary()
        #expect(summary.dialog == .unfinishedWithValues(count: 1))
        #expect(summary.uncheckedWithValues == 1 && summary.uncheckedWithoutValues == 1)
        // Only empty unchecked sets left.
        try engine.setValues(sets(row)[1], weight: nil, reps: nil, durationSeconds: nil)
        summary = try engine.finishSummary()
        #expect(summary.dialog == .unfinishedWithoutValues(count: 2))
        // Everything checked.
        try engine.removeSet(sets(row)[2])
        try engine.removeSet(sets(row)[1])
        #expect(try engine.finishSummary().dialog == FinishDialog.none)
    }

    @Test func finishDiscardsUnfinishedSetsAndEmptyExercises() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let workout = try engine.startEmpty()
        let squat = try loggedSquat(rig, engine: engine)
        let curl = try engine.addExercise(try rig.info(LibraryFixture.curl))
        try engine.setValues(sets(curl)[0], weight: 10, reps: 10, durationSeconds: nil)  // unchecked, with values
        rig.clock.advance(600)

        let summary = try engine.finish(unfinished: .discard)
        #expect(workout.finishedAt == rig.clock.date)
        #expect(engine.workout == nil)
        #expect(rows(workout).map(\.id) == [squat.id])  // curl has no checked set
        #expect(sets(squat).count == 2 && sets(squat).map(\.position) == [0, 1])
        #expect(sets(squat).allSatisfy { $0.completed })
        #expect(summary.setCount == 2 && summary.exerciseCount == 1 && summary.duration == 600)
        #expect(try rig.context.fetchCount(FetchDescriptor<WorkoutSet>()) == 2)
        #expect(try rig.context.fetchCount(FetchDescriptor<WorkoutExercise>()) == 1)
        #expect(try !rig.context.hasChanges)
        // A new workout can start now.
        #expect(try engine.startEmpty().id != workout.id)
    }

    @Test func finishCanCompleteUnfinishedSetsWithValues() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let workout = try engine.startEmpty()
        let squat = try loggedSquat(rig, engine: engine)
        try engine.setValues(sets(squat)[2], weight: 100, reps: 3, durationSeconds: nil)
        rig.clock.advance(600)
        let summary = try engine.finish(unfinished: .complete)
        let kept = sets(squat)
        #expect(kept.count == 3 && kept.allSatisfy { $0.completed })
        #expect(kept[2].completedAt == rig.clock.date)
        #expect(summary.setCount == 3)
        #expect(workout.finishedAt != nil)
    }

    @Test func finishClampsFinishedAtToStartedAt() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let workout = try engine.startEmpty()
        _ = try loggedSquat(rig, engine: engine)
        rig.clock.advance(-500)  // clock went backwards
        let summary = try engine.finish(unfinished: .discard)
        #expect(workout.finishedAt == workout.startedAt)
        #expect(summary.duration == 0)
    }

    @Test func finishWithNothingCheckedIsRefused() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let workout = try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        try engine.setValues(sets(row)[0], weight: 50, reps: 5, durationSeconds: nil)
        #expect(throws: ActiveWorkoutError.nothingLogged) { try engine.finish(unfinished: .complete) }
        #expect(workout.finishedAt == nil && engine.workout === workout)
        #expect(sets(row).count == 3)
    }

    @Test func finishedWorkoutBecomesPreviousForTheNextOne() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        _ = try loggedSquat(rig, engine: engine)
        rig.clock.advance(600)
        try engine.finish(unfinished: .discard)
        rig.clock.advance(86_400)
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        #expect(engine.previous(for: sets(row)[0])?.weight == 105)
    }

    @Test func discardDeletesTheWorkoutAndItsRows() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        _ = try loggedSquat(rig, engine: engine)
        try engine.discard()
        #expect(engine.workout == nil)
        #expect(try rig.context.fetchCount(FetchDescriptor<Workout>()) == 0)
        #expect(try rig.context.fetchCount(FetchDescriptor<WorkoutExercise>()) == 0)
        #expect(try rig.context.fetchCount(FetchDescriptor<WorkoutSet>()) == 0)
        #expect(try rig.makeEngine().workout == nil)
    }
}
