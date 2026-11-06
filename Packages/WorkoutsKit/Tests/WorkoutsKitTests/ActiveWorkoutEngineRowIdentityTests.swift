import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

/// Behaviour tied to a row's exercise: timed columns after a replace, Previous per repeated row, warm-ups from the plan.
@Suite struct EngineRowIdentityTests {
    private func sets(_ row: WorkoutExercise) -> [WorkoutSet] {
        (row.sets ?? []).sorted { $0.position < $1.position }
    }

    private func rows(_ workout: Workout) -> [WorkoutExercise] {
        (workout.exercises ?? []).sorted { $0.position < $1.position }
    }

    private func template(_ rig: EngineTests.Rig, exercise: UUID, name: String, sets values: [(Double?, Int?, Int?)])
        throws -> Template
    {
        let template = Template(name: name)
        rig.context.insert(template)
        let row = TemplateExercise(exerciseID: exercise, exerciseName: name, position: 0, unit: .kg)
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

    @Test func replacingATimedExerciseWithARepsOneDropsTheTimeColumn() throws {
        let rig = try EngineTests.Rig()
        let plank = try template(rig, exercise: LibraryFixture.etirement, name: "Stretch", sets: [(nil, nil, 60)])
        let engine = try rig.makeEngine()
        let workout = try engine.start(from: plank)
        let row = try #require(rows(workout).first)
        #expect(engine.isTimed(row))
        try engine.replaceExercise(row, with: try rig.info(LibraryFixture.curl))
        #expect(engine.plan(for: sets(row)[0]) == nil)
        #expect(!engine.isTimed(row))
    }

    @Test func secondRowOfTheSameExerciseShowsTheSecondPastRow() throws {
        let rig = try EngineTests.Rig()
        rig.settings.defaultUnit = .kg
        let start = rig.clock.date.addingTimeInterval(-86_400)
        let past = Workout(name: "Past", startedAt: start, finishedAt: start.addingTimeInterval(3600))
        rig.context.insert(past)
        for (position, value) in [(100.0, 5), (60.0, 12)].enumerated() {
            let row = WorkoutExercise(
                exerciseID: LibraryFixture.squat,
                exerciseName: "Squat",
                position: position,
                unit: .kg
            )
            rig.context.insert(row)
            row.workout = past
            let set = WorkoutSet(
                position: 0,
                kind: .normal,
                weight: value.0,
                reps: value.1,
                completed: true,
                completedAt: start
            )
            rig.context.insert(set)
            set.workoutExercise = row
        }
        try rig.context.save()

        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let squat = try rig.info(LibraryFixture.squat)
        let first = try engine.addExercise(squat)
        let second = try engine.addExercise(squat)
        let third = try engine.addExercise(squat)
        #expect(engine.previous(for: sets(first)[0]) == PreviousSet(kind: .normal, weight: 100, reps: 5))
        #expect(engine.previous(for: sets(second)[0]) == PreviousSet(kind: .normal, weight: 60, reps: 12))
        // A row with no counterpart last time falls back to the first row's Previous.
        #expect(engine.previous(for: sets(third)[0]) == PreviousSet(kind: .normal, weight: 100, reps: 5))
    }

    @Test func addWarmupSetsWorksRightAfterStartingFromATemplateUsingThePlanWeight() throws {
        let rig = try EngineTests.Rig()
        let plan = try template(
            rig,
            exercise: LibraryFixture.squat,
            name: "Squat",
            sets: [(100, 5, nil), (100, 5, nil), (100, 5, nil)]
        )
        let engine = try rig.makeEngine()
        let workout = try engine.start(from: plan)
        let row = try #require(rows(workout).first)
        #expect(sets(row).allSatisfy { $0.weight == nil })
        #expect(try engine.addWarmupSets(to: row))
        let warmups = sets(row).filter { $0.kind == .warmup }
        #expect(!warmups.isEmpty)
        #expect(sets(row).filter { $0.kind != .warmup }.count == 3)
        #expect(warmups.allSatisfy { ($0.weight ?? 0) > 0 && ($0.weight ?? 0) < 100 })
    }

    @Test func addWarmupSetsStillRefusesWithoutAnyWorkingWeight() throws {
        let rig = try EngineTests.Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let row = try engine.addExercise(try rig.info(LibraryFixture.squat))
        #expect(try engine.addWarmupSets(to: row) == false)
    }
}
