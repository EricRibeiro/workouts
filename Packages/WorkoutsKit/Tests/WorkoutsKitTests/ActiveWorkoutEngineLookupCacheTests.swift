import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

/// The engine's cached Previous, plan and timed lookups: still right after every structural edit, and actually cached.
@Suite struct EngineLookupCacheTests {
    private func sets(_ row: WorkoutExercise) -> [WorkoutSet] {
        (row.sets ?? []).sorted { $0.position < $1.position }
    }

    private func rows(_ workout: Workout) -> [WorkoutExercise] {
        (workout.exercises ?? []).sorted { $0.position < $1.position }
    }

    private func template(_ rig: EngineTests.Rig, exercise: UUID, sets values: [(Double?, Int?, Int?)]) throws
        -> Template
    {
        let template = Template(name: "T", updatedAt: rig.clock.date)
        rig.context.insert(template)
        let row = TemplateExercise(exerciseID: exercise, exerciseName: "T", position: 0, unit: .kg)
        rig.context.insert(row)
        row.template = template
        for (index, value) in values.enumerated() {
            let set = TemplateSet(position: index, weight: value.0, reps: value.1, durationSeconds: value.2)
            rig.context.insert(set)
            set.templateExercise = row
        }
        try rig.context.save()
        return template
    }

    private func past(
        _ rig: EngineTests.Rig,
        daysAgo: Double,
        rows values: [[(Double, Int, SetKind)]],
        unit: WeightUnit = .kg
    ) throws -> Workout {
        let start = rig.clock.date.addingTimeInterval(-86_400 * daysAgo)
        let workout = Workout(name: "Past", startedAt: start, finishedAt: start.addingTimeInterval(3600))
        rig.context.insert(workout)
        for (position, sets) in values.enumerated() {
            let row = WorkoutExercise(
                exerciseID: LibraryFixture.squat,
                exerciseName: "Squat",
                position: position,
                unit: unit
            )
            rig.context.insert(row)
            row.workout = workout
            for (index, value) in sets.enumerated() {
                let set = WorkoutSet(
                    position: index,
                    kind: value.2,
                    weight: value.0,
                    reps: value.1,
                    completed: true,
                    completedAt: start
                )
                rig.context.insert(set)
                set.workoutExercise = row
            }
        }
        try rig.context.save()
        return workout
    }

    private func squatRig() throws -> (EngineTests.Rig, ActiveWorkoutEngine, WorkoutExercise) {
        let rig = try EngineTests.Rig()
        rig.settings.defaultUnit = .kg
        _ = try past(rig, daysAgo: 1, rows: [[(60, 8, .warmup), (100, 5, .normal), (110, 5, .normal)]])
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        return (rig, engine, row)
    }

    @Test func repeatedLookupsAreServedFromTheCache() throws {
        let rig = try EngineTests.Rig()
        defer { withExtendedLifetime(rig) {} }
        _ = try past(rig, daysAgo: 1, rows: [[(100, 5, .normal), (110, 5, .normal), (120, 5, .normal)]])
        let plan = try template(rig, exercise: LibraryFixture.squat, sets: [(90, 8, nil), (95, 8, nil), (100, 8, nil)])
        let engine = try rig.makeEngine()
        let workout = try engine.start(from: plan)
        let row = try #require(rows(workout).first)
        var computed: [LookupKind] = []
        engine.lookupProbe = { computed.append($0) }

        for _ in 0..<3 {
            for set in sets(row) {
                _ = engine.previous(for: set)
                _ = engine.plan(for: set)
                _ = engine.canCheck(set)
            }
            _ = engine.isTimed(row)
        }
        #expect(computed.filter { $0 == .previous }.count == 3)
        #expect(computed.filter { $0 == .plan }.count == 3)

        // Typing and checking read the same Previous and plan, so they do not recompute them.
        let first = try #require(sets(row).first)
        try engine.setValues(first, weight: 105, reps: 4, durationSeconds: nil)
        try engine.check(first)
        _ = engine.canCheck(first)
        #expect(computed.count == 6)
    }

    @Test func aTimedAnswerOfFalseIsCachedAndStillSeesATypedDuration() throws {
        let (rig, engine, row) = try squatRig()
        defer { withExtendedLifetime(rig) {} }
        var computed = 0
        engine.lookupProbe = { _ in computed += 1 }
        #expect(!engine.isTimed(row))
        let afterFirst = computed
        #expect(!engine.isTimed(row))
        #expect(computed == afterFirst)
        try engine.setValues(try #require(sets(row).first), weight: nil, reps: nil, durationSeconds: 30)
        #expect(engine.isTimed(row))
    }

    @Test func changingASetKindRemapsPrevious() throws {
        let (rig, engine, row) = try squatRig()
        defer { withExtendedLifetime(rig) {} }
        let all = sets(row)
        #expect(engine.previous(for: all[0]) == PreviousSet(kind: .normal, weight: 100, reps: 5))
        #expect(engine.previous(for: all[2]) == nil)
        try engine.setKind(all[0], to: .warmup)
        #expect(engine.previous(for: all[0]) == PreviousSet(kind: .warmup, weight: 60, reps: 8))
        #expect(engine.previous(for: all[1]) == PreviousSet(kind: .normal, weight: 100, reps: 5))
        #expect(engine.previous(for: all[2]) == PreviousSet(kind: .normal, weight: 110, reps: 5))
    }

    @Test func addingAndRemovingASetKeepsPreviousRight() throws {
        let (rig, engine, row) = try squatRig()
        defer { withExtendedLifetime(rig) {} }
        let original = sets(row)
        #expect(original.map { engine.previous(for: $0)?.weight } == [100, 110, nil])
        let added = try engine.addSet(to: row)
        #expect(engine.previous(for: added) == nil)
        #expect(sets(row).map { engine.previous(for: $0)?.weight } == [100, 110, nil, nil])
        try engine.removeSet(original[0])
        #expect(sets(row).map { engine.previous(for: $0)?.weight } == [100, 110, nil])
    }

    @Test func addingWarmupSetsKeepsPreviousRight() throws {
        let (rig, engine, row) = try squatRig()
        defer { withExtendedLifetime(rig) {} }
        for set in sets(row) { try engine.setValues(set, weight: 100, reps: 5, durationSeconds: nil) }
        #expect(sets(row).map { engine.previous(for: $0)?.weight } == [100, 110, nil])
        #expect(try engine.addWarmupSets(to: row))
        let all = sets(row)
        #expect(all.count > 3)
        let warmups = all.filter { $0.kind == .warmup }
        #expect(!warmups.isEmpty)
        // The first warm-up takes the past warm-up; the working sets still take 100 and 110.
        #expect(engine.previous(for: warmups[0]) == PreviousSet(kind: .warmup, weight: 60, reps: 8))
        let working = all.filter { $0.kind != .warmup }
        #expect(working.map { engine.previous(for: $0)?.weight } == [100, 110, nil])
    }

    @Test func replacingTheExerciseRereadsPreviousAndTimedness() throws {
        let rig = try EngineTests.Rig()
        defer { withExtendedLifetime(rig) {} }
        rig.settings.defaultUnit = .kg
        _ = try past(rig, daysAgo: 1, rows: [[(100, 5, .normal)]])
        rig.finishedWorkout(
            exercise: LibraryFixture.curl,
            unit: .kg,
            sets: [(weight: 20, reps: 10, kind: .normal)],
            startedAt: rig.clock.date.addingTimeInterval(-86_400)
        )
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let first = try #require(sets(row).first)
        #expect(engine.previous(for: first) == PreviousSet(kind: .normal, weight: 100, reps: 5))
        #expect(!engine.isTimed(row))
        try engine.replaceExercise(row, with: try rig.info(LibraryFixture.curl))
        #expect(engine.previous(for: first) == PreviousSet(kind: .normal, weight: 20, reps: 10))
    }

    @Test func replacingATimedPlanWithARepsExerciseDropsTimedAfterBeingCached() throws {
        let rig = try EngineTests.Rig()
        defer { withExtendedLifetime(rig) {} }
        let plank = try template(rig, exercise: LibraryFixture.etirement, sets: [(nil, nil, 60)])
        let engine = try rig.makeEngine()
        let workout = try engine.start(from: plank)
        let row = try #require(rows(workout).first)
        #expect(engine.plan(for: sets(row)[0])?.durationSeconds == 60)
        #expect(engine.isTimed(row))
        try engine.replaceExercise(row, with: try rig.info(LibraryFixture.curl))
        #expect(engine.plan(for: sets(row)[0]) == nil)
        #expect(!engine.isTimed(row))
    }

    @Test func reorderingRowsOfTheSameExerciseSwapsTheirPrevious() throws {
        let rig = try EngineTests.Rig()
        defer { withExtendedLifetime(rig) {} }
        rig.settings.defaultUnit = .kg
        _ = try past(rig, daysAgo: 1, rows: [[(100, 5, .normal)], [(60, 12, .normal)]])
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let squat = try rig.info(LibraryFixture.squat)
        let first = try engine.addExercise(squat)
        let second = try engine.addExercise(squat)
        #expect(engine.previous(for: sets(first)[0])?.weight == 100)
        #expect(engine.previous(for: sets(second)[0])?.weight == 60)
        try engine.reorderExercises([second, first])
        #expect(engine.previous(for: sets(first)[0])?.weight == 60)
        #expect(engine.previous(for: sets(second)[0])?.weight == 100)
        try engine.removeExercise(second)
        #expect(engine.previous(for: sets(first)[0])?.weight == 100)
    }

    @Test func reloadingPreviousAfterDeletingTheSourceWorkoutFallsBackToTheOlderOne() throws {
        let rig = try EngineTests.Rig()
        defer { withExtendedLifetime(rig) {} }
        rig.settings.defaultUnit = .kg
        _ = try past(rig, daysAgo: 7, rows: [[(80, 6, .normal)]])
        let newer = try past(rig, daysAgo: 1, rows: [[(100, 5, .normal)]])
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let first = try #require(sets(row).first)
        #expect(engine.previous(for: first)?.weight == 100)

        rig.context.delete(newer)
        try rig.context.save()
        try engine.reloadPrevious()
        #expect(engine.previous(for: first)?.weight == 80)
    }

    @Test func aTemplateEditIsSeenByThePlan() throws {
        let rig = try EngineTests.Rig()
        defer { withExtendedLifetime(rig) {} }
        let plan = try template(rig, exercise: LibraryFixture.squat, sets: [(100, 5, nil)])
        let engine = try rig.makeEngine()
        let workout = try engine.start(from: plan)
        let row = try #require(rows(workout).first)
        let first = try #require(sets(row).first)
        #expect(engine.plan(for: first)?.weight == 100)

        let planned = try #require(plan.exercises?.first?.sets?.first)
        planned.weight = 120
        rig.clock.advance(60)
        plan.updatedAt = rig.clock.date
        #expect(engine.plan(for: first)?.weight == 120)
    }

    @Test func changingTheUnitReconvertsPrevious() throws {
        let (rig, engine, row) = try squatRig()
        defer { withExtendedLifetime(rig) {} }
        let first = try #require(sets(row).first)
        #expect(engine.previous(for: first)?.weight == 100)
        try engine.setUnit(.lb, for: row)
        #expect(engine.previous(for: first)?.weight == 220.5)
    }

    @Test func aFinishedWorkoutBecomesPreviousForTheNextOneAfterTheCachesWereFilled() throws {
        let (rig, engine, row) = try squatRig()
        defer { withExtendedLifetime(rig) {} }
        let first = try #require(sets(row).first)
        try engine.setValues(first, weight: 130, reps: 3, durationSeconds: nil)
        try engine.check(first)
        #expect(engine.previous(for: first)?.weight == 100)
        try engine.finish(unfinished: .discard)
        try engine.startEmpty()
        let next = try engine.addExercise(try rig.info(LibraryFixture.squat))
        #expect(
            engine.previous(for: try #require(sets(next).first)) == PreviousSet(kind: .normal, weight: 130, reps: 3)
        )
    }
}
