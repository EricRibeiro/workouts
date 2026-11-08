import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct TemplateUpdateTests {
    private let bench = UUID()
    private let row = UUID()
    private let squat = UUID()

    /// A template of Bench (3 sets, 100 x 5) and Row (2 sets, 60 x 8), and a finished workout that copies it exactly.
    private func makePair(_ context: ModelContext) -> (Template, Workout) {
        let template = Template(name: "Push")
        context.insert(template)
        let workout = Workout(name: "Push", finishedAt: Date(), template: template)
        context.insert(workout)
        for (position, (id, name, sets, weight, reps)) in [
            (bench, "Bench", 3, 100.0, 5), (row, "Row", 2, 60.0, 8),
        ].enumerated() {
            let plan = TemplateExercise(exerciseID: id, exerciseName: name, position: position, template: template)
            context.insert(plan)
            let done = WorkoutExercise(exerciseID: id, exerciseName: name, position: position, workout: workout)
            context.insert(done)
            for index in 0..<sets {
                context.insert(TemplateSet(position: index, weight: weight, reps: reps, templateExercise: plan))
                context.insert(
                    WorkoutSet(
                        position: index,
                        weight: weight,
                        reps: reps,
                        completed: true,
                        workoutExercise: done
                    )
                )
            }
        }
        return (template, workout)
    }

    private func workoutSets(_ workout: Workout, exercise: Int) -> [WorkoutSet] {
        let rows = (workout.exercises ?? []).sorted { $0.position < $1.position }
        return (rows[exercise].sets ?? []).sorted { $0.position < $1.position }
    }

    private func templateRows(_ template: Template) -> [TemplateExercise] {
        (template.exercises ?? []).sorted { $0.position < $1.position }
    }

    private func templateSets(_ plan: TemplateExercise) -> [TemplateSet] {
        (plan.sets ?? []).sorted { $0.position < $1.position }
    }

    // MARK: diff

    @Test func identicalWorkoutHasNothingToUpdate() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .none)
    }

    @Test func changedWeightOrRepsIsValuesOnly() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        workoutSets(workout, exercise: 0)[1].weight = 105
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .valuesOnly)
        workoutSets(workout, exercise: 0)[1].weight = 100
        workoutSets(workout, exercise: 1)[0].reps = 10
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .valuesOnly)
    }

    @Test func missingAndZeroValuesAreTheSame() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        templateSets(templateRows(template)[1])[0].weight = nil
        workoutSets(workout, exercise: 1)[0].weight = 0
        templateSets(templateRows(template)[1])[0].reps = 8
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .none)
    }

    @Test func sameWeightInAnotherUnitIsNoDifference() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        let plan = templateRows(template)[0]
        plan.unit = .kg
        for set in templateSets(plan) { set.weight = 100 }
        let done = (workout.exercises ?? []).first { $0.exerciseID == bench }
        done?.unit = .lb
        for set in workoutSets(workout, exercise: 0) { set.weight = 100 / kgPerLb }
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .none)
    }

    @Test func barChangeIsValuesOnly() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        let done = (workout.exercises ?? []).first { $0.exerciseID == bench }
        done?.barType = .ez
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .valuesOnly)
        done?.barType = .custom
        done?.barWeight = 15
        templateRows(template)[0].barType = .custom
        templateRows(template)[0].barWeight = 20
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .valuesOnly)
        templateRows(template)[0].barWeight = 15
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .none)
    }

    @Test func droppedSetAddedExerciseAndReorderAreStructure() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        // A dropped set.
        let dropped = workoutSets(workout, exercise: 0)[2]
        context.delete(dropped)
        try context.save()
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .structure)
    }

    @Test func addedExerciseIsStructure() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        let extra = WorkoutExercise(exerciseID: squat, exerciseName: "Squat", position: 2, workout: workout)
        context.insert(extra)
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .structure)
    }

    @Test func reorderedExercisesAreStructure() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        for exercise in workout.exercises ?? [] { exercise.position = 1 - exercise.position }
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .structure)
    }

    @Test func changedSetKindAndSupersetAreStructure() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        workoutSets(workout, exercise: 0)[0].kind = .warmup
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .structure)
        workoutSets(workout, exercise: 0)[0].kind = .normal
        for exercise in workout.exercises ?? [] { exercise.supersetGroup = 4 }
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .structure)
        // The same grouping under another number is no change.
        for exercise in templateRows(template) { exercise.supersetGroup = 1 }
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .none)
    }

    // MARK: apply

    @Test func valuesOnlyCopiesValuesAndKeepsStructure() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        workoutSets(workout, exercise: 0)[0].weight = 110
        context.delete(workoutSets(workout, exercise: 0)[2])
        try context.save()
        let extra = WorkoutExercise(exerciseID: squat, exerciseName: "Squat", position: 2, workout: workout)
        context.insert(extra)

        try TemplateUpdate.apply(.valuesOnly, template: template, workout: workout, in: context)

        let rows = templateRows(template)
        #expect(rows.map(\.exerciseName) == ["Bench", "Row"])
        #expect(templateSets(rows[0]).count == 3, "structure stays")
        #expect(templateSets(rows[0]).map(\.weight) == [110, 100, 100])
        #expect(templateSets(rows[1]).map(\.reps) == [8, 8])
    }

    @Test func valuesOnlyConvertsTemplateSetsWithoutACounterpartWhenTheUnitSwitches() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        // Bench was planned as 3 x 100 lb; the workout switched it to kg and logged two sets of 60, the third undone.
        let plan = try #require(templateRows(template).first)
        plan.unit = .lb
        let done = try #require((workout.exercises ?? []).first { $0.position == 0 })
        done.unit = .kg
        for set in workoutSets(workout, exercise: 0) { set.weight = 60 }
        context.delete(workoutSets(workout, exercise: 0)[2])
        try context.save()

        try TemplateUpdate.apply(.valuesOnly, template: template, workout: workout, in: context)

        let bench = templateRows(template)[0]
        #expect(bench.unit == .kg)
        #expect(templateSets(bench).map(\.weight) == [60, 60, 45.5], "100 lb is 45.359 kg, rounded to 45.5")
    }

    @Test func valuesOnlyPairsSetsByKindSoWarmupsDoNotShiftWorkingSets() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        // Two warm-ups are added in front of Bench's three working sets (100 x 5); the lifter also did 105 on set 2.
        let bench = try #require((workout.exercises ?? []).first { $0.position == 0 })
        for set in bench.sets ?? [] { set.position += 2 }
        for (index, weight) in [20.0, 40.0].enumerated() {
            context.insert(
                WorkoutSet(
                    position: index,
                    kind: .warmup,
                    weight: weight,
                    reps: 10,
                    completed: true,
                    workoutExercise: bench
                )
            )
        }
        workoutSets(workout, exercise: 0)[3].weight = 105

        try TemplateUpdate.apply(.valuesOnly, template: template, workout: workout, in: context)

        let sets = templateSets(templateRows(template)[0])
        #expect(sets.count == 3, "no warm-ups are added to the template")
        #expect(sets.allSatisfy { $0.kind == .normal })
        #expect(sets.map(\.weight) == [100, 105, 100])
        #expect(sets.map(\.reps) == [5, 5, 5])
    }

    @Test func valuesOnlyIgnoresUncheckedWorkoutSets() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        let skipped = workoutSets(workout, exercise: 0)[2]
        skipped.weight = 5
        skipped.completed = false
        workoutSets(workout, exercise: 0)[0].weight = 110

        try TemplateUpdate.apply(.valuesOnly, template: template, workout: workout, in: context)

        #expect(templateSets(templateRows(template)[0]).map(\.weight) == [110, 100, 100])
    }

    @Test func templateAndValuesMirrorsTheWorkout() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        // Drop the last bench set, swap the order, add a squat with two sets, change a value.
        context.delete(workoutSets(workout, exercise: 0)[2])
        try context.save()
        workoutSets(workout, exercise: 0)[0].weight = 110
        for exercise in workout.exercises ?? [] { exercise.position = 1 - exercise.position }
        let extra = WorkoutExercise(exerciseID: squat, exerciseName: "Squat", position: 2, workout: workout)
        context.insert(extra)
        for index in 0..<2 {
            context.insert(
                WorkoutSet(
                    position: index,
                    kind: index == 0 ? .warmup : .normal,
                    weight: 140,
                    reps: 3,
                    workoutExercise: extra
                )
            )
        }

        try TemplateUpdate.apply(.templateAndValues, template: template, workout: workout, in: context)

        let rows = templateRows(template)
        #expect(rows.map(\.exerciseName) == ["Row", "Bench", "Squat"])
        #expect(rows.map(\.position) == [0, 1, 2])
        #expect(templateSets(rows[1]).map(\.weight) == [110, 100])
        #expect(templateSets(rows[2]).map(\.kind) == [.warmup, .normal])
        #expect(templateSets(rows[2]).map(\.weight) == [140, 140])
        #expect(TemplateUpdate.diff(template: template, workout: workout) == .none)
        // No orphaned sets are left behind.
        #expect(try context.fetch(FetchDescriptor<TemplateSet>()).count == 2 + 2 + 2)
    }

    @Test func templateAndValuesDeletesExercisesTheWorkoutDropped() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        let dropped = (workout.exercises ?? []).first { $0.exerciseID == row }
        if let dropped { context.delete(dropped) }
        try context.save()
        try TemplateUpdate.apply(.templateAndValues, template: template, workout: workout, in: context)
        #expect(templateRows(template).map(\.exerciseName) == ["Bench"])
        #expect(try context.fetch(FetchDescriptor<TemplateSet>()).count == 3)
    }

    @Test func keepChangesNothing() throws {
        let context = try makeTestContext()
        let (template, workout) = makePair(context)
        workoutSets(workout, exercise: 0)[0].weight = 110
        let before = template.updatedAt
        try TemplateUpdate.apply(.keep, template: template, workout: workout, in: context)
        #expect(templateSets(templateRows(template)[0])[0].weight == 100)
        #expect(template.updatedAt == before)
    }
}

@Suite struct TemplatePreviewRowTests {
    @Test func rowsCollapseIdenticalSetsAndNameKinds() throws {
        let context = try makeTestContext()
        let template = Template(name: "Push")
        context.insert(template)
        let plan = TemplateExercise(exerciseName: "Bench", position: 0, supersetGroup: 2, unit: .kg, template: template)
        context.insert(plan)
        let specs: [(SetKind, Double?, Int?)] = [
            (.warmup, 40, 8), (.normal, 100, 5), (.normal, 100, 5), (.normal, 100, 5), (.normal, nil, nil),
        ]
        for (index, spec) in specs.enumerated() {
            context.insert(
                TemplateSet(position: index, kind: spec.0, weight: spec.1, reps: spec.2, templateExercise: plan)
            )
        }
        let rows = TemplatePreviewRow.rows(for: template)
        #expect(rows.count == 1)
        #expect(rows[0].title == "5 × Bench")
        #expect(rows[0].supersetGroup == 2)
        #expect(rows[0].plan == "Warm-up 40 kg × 8 · 3 × 100 kg × 5")
        #expect(rows[0].accessibilityLabel == "5 sets of Bench, Warm-up 40 kg × 8 · 3 × 100 kg × 5")
    }

    @Test func emptyPlanHasNoText() {
        #expect(TemplatePreviewRow.planText([TemplateSet(), TemplateSet()], unit: .lb).isEmpty)
    }
}
