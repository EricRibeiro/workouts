import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite @MainActor struct PastWorkoutDraftTests {
    private let start = TestSupport.referenceDate

    /// Two exercises: bench (2 sets) and rows (1 set), both in superset 1 with RPE 8 on every set, 50 minutes long.
    private func workout(_ context: ModelContext) -> Workout {
        let workout = Workout(
            name: "Push",
            startedAt: start,
            finishedAt: start.addingTimeInterval(50 * 60)
        )
        context.insert(workout)
        for (position, spec) in [("Bench", 2), ("Row", 1)].enumerated() {
            let row = WorkoutExercise(
                exerciseName: spec.0,
                position: position,
                supersetGroup: 1,
                unit: .kg,
                workout: workout
            )
            context.insert(row)
            for index in 0..<spec.1 {
                context.insert(
                    WorkoutSet(
                        position: index,
                        weight: 100,
                        reps: 5,
                        completed: true,
                        completedAt: start.addingTimeInterval(600),
                        rpe: 8,
                        workoutExercise: row
                    )
                )
            }
        }
        return workout
    }

    @Test func freshDraftIsCleanAndReadsTheWorkout() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let model = workout(holder.mainContext)
        let draft = PastWorkoutDraft(model)
        #expect(!draft.hasChanges(from: PastWorkoutDraft(model)))
        #expect(draft.name == "Push")
        #expect(draft.durationMinutes == 50)
        #expect(draft.exercises.map(\.name) == ["Bench", "Row"])
        #expect(draft.exercises[0].sets.count == 2)
    }

    @Test func everyKindOfEditMarksTheDraftDirty() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let original = PastWorkoutDraft(workout(holder.mainContext))
        let setID = original.exercises[0].sets[0].id

        var weight = original
        weight.setWeight(105, for: setID)
        var count = original
        count.setCount(6, for: setID)
        var kind = original
        kind.cycleKind(of: setID)
        var added = original
        added.addSet(to: original.exercises[0].id)
        var deleted = original
        deleted.deleteSet(setID)
        var started = original
        started.startedAt = original.startedAt.addingTimeInterval(60)
        var minutes = original
        minutes.setDurationMinutes(51)
        var renamed = original
        renamed.rename(to: "Pull")
        var reordered = original
        reordered.reorder(original.exercises.map(\.id).reversed())

        for edited in [weight, count, kind, added, deleted, started, minutes, renamed, reordered] {
            #expect(edited.hasChanges(from: original))
        }
        // Changing a value back leaves it clean again.
        weight.setWeight(100, for: setID)
        #expect(!weight.hasChanges(from: original))
    }

    @Test func durationNeverGoesNegativeAndRenameIgnoresBlank() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        var draft = PastWorkoutDraft(workout(holder.mainContext))
        draft.setDurationMinutes(-5)
        #expect(draft.durationSeconds == 0)
        #expect(draft.endedAt == draft.startedAt)
        draft.rename(to: "   ")
        #expect(draft.name == "Push")
        draft.rename(to: "  Legs ")
        #expect(draft.name == "Legs")
    }

    @Test func durationMinutesFloorLikeTheHistoryRows() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let model = workout(holder.mainContext)
        model.finishedAt = start.addingTimeInterval(50 * 60 + 45)
        let draft = PastWorkoutDraft(model)
        #expect(draft.durationMinutes == 50)
        #expect(HistoryList.durationText(seconds: draft.durationSeconds) == "50min")
    }

    @Test func durationClampsToADay() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        var draft = PastWorkoutDraft(workout(holder.mainContext))
        draft.setDurationMinutes(5000)
        #expect(draft.durationMinutes == 1440)
        draft.setDurationMinutes(1440)
        #expect(draft.durationSeconds == 86_400)
    }

    @Test func addSetCopiesTheLastAndWarmupBecomesNormal() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        var draft = PastWorkoutDraft(workout(holder.mainContext))
        let exercise = draft.exercises[0].id
        draft.cycleKind(of: draft.exercises[0].sets[1].id)  // normal -> warmup
        #expect(draft.exercises[0].sets[1].kind == .warmup)
        let new = UUID()
        draft.addSet(to: exercise, id: new)
        let added = draft.exercises[0].sets[2]
        #expect(added.id == new)
        #expect(added.kind == .normal)
        #expect(added.weight == 100)
        #expect(added.reps == 5)
    }

    @Test func reorderNeedsEveryIDExactlyOnce() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        var draft = PastWorkoutDraft(workout(holder.mainContext))
        let ids = draft.exercises.map(\.id)
        draft.reorder([ids[0]])
        draft.reorder([ids[0], ids[0]])
        #expect(draft.exercises.map(\.id) == ids)
        draft.reorder(ids.reversed())
        #expect(draft.exercises.map(\.id) == ids.reversed())
    }

    @Test func timedExercisesEditSecondsNotReps() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let model = workout(context)
        model.exercises?.first { $0.exerciseName == "Row" }?.sets?.first?.durationSeconds = 30
        var draft = PastWorkoutDraft(model)
        let row = draft.exercises[1]
        #expect(row.isTimed)
        draft.setCount(45, for: row.sets[0].id)
        #expect(draft.exercises[1].sets[0].durationSeconds == 45)
        #expect(draft.exercises[1].sets[0].reps == 5)
    }

    @Test func saveWritesValuesKeepsHiddenFieldsAndMovesTheEnd() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let model = workout(context)
        let setModel = try #require(model.exercises?.first { $0.position == 0 }?.sets?.first { $0.position == 0 })
        var draft = PastWorkoutDraft(model)
        draft.rename(to: "Heavy Push")
        draft.setWeight(110, for: setModel.id)
        draft.setDurationMinutes(40)
        draft.startedAt = start.addingTimeInterval(3600)
        let now = start.addingTimeInterval(86_400)
        try draft.save(to: model, in: context, now: now)

        #expect(model.name == "Heavy Push")
        #expect(model.startedAt == start.addingTimeInterval(3600))
        #expect(model.finishedAt == start.addingTimeInterval(3600 + 40 * 60))
        #expect(model.updatedAt == now)
        #expect(setModel.weight == 110)
        #expect(setModel.completed)
        #expect(setModel.rpe == 8)  // not shown, not touched
        #expect(setModel.completedAt == start.addingTimeInterval(600 + 3600))  // moved with the start
    }

    private func matched(_ model: Workout) {
        model.healthWorkoutID = "HK-1"
        model.healthCheckedAt = start.addingTimeInterval(7200)
        model.activeEnergyKcal = 300
        model.avgHeartRate = 120
        model.heartRateSeriesData = Data([1])
        model.weatherTemperatureCelsius = 12
    }

    @Test func changingTheStartOrDurationClearsTheFitnessMatchSoItIsMatchedAgain() throws {
        for change in [
            { (draft: inout PastWorkoutDraft) in draft.startedAt = draft.startedAt.addingTimeInterval(3600) },
            { (draft: inout PastWorkoutDraft) in draft.setDurationMinutes(40) },
        ] {
            let holder = try makeTestContainer()
            defer { withExtendedLifetime(holder) {} }
            let context = holder.mainContext
            let model = workout(context)
            matched(model)
            var draft = PastWorkoutDraft(model)
            change(&draft)
            try draft.save(to: model, in: context, now: start.addingTimeInterval(86_400))

            #expect(model.healthWorkoutID == nil)
            #expect(model.healthCheckedAt == nil)
            #expect(model.activeEnergyKcal == nil)
            #expect(model.avgHeartRate == nil)
            #expect(model.heartRateSeriesData == nil)
            #expect(model.weatherTemperatureCelsius == nil)
        }
    }

    @Test func unchangedTimesKeepTheFitnessMatch() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let model = workout(context)
        matched(model)
        var draft = PastWorkoutDraft(model)
        draft.rename(to: "Renamed")
        try draft.save(to: model, in: context, now: start.addingTimeInterval(86_400))

        #expect(model.name == "Renamed")
        #expect(model.healthWorkoutID == "HK-1")
        #expect(model.healthCheckedAt == start.addingTimeInterval(7200))
        #expect(model.activeEnergyKcal == 300)
        #expect(model.heartRateSeriesData == Data([1]))
    }

    @Test func saveDropsEmptySetsEmptyExercisesAndLoneSupersets() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let model = workout(context)
        var draft = PastWorkoutDraft(model)
        // Row loses its only set: the exercise goes, and Bench is alone in superset 1.
        draft.deleteSet(draft.exercises[1].sets[0].id)
        // Bench's second set is emptied: dropped; a new filled set is added and completed.
        let emptied = draft.exercises[0].sets[1].id
        draft.setWeight(nil, for: emptied)
        draft.setCount(nil, for: emptied)
        let new = UUID()
        draft.addSet(to: draft.exercises[0].id, id: new)
        draft.setWeight(90, for: new)
        try draft.save(to: model, in: context)

        let rows = (model.exercises ?? []).sorted { $0.position < $1.position }
        #expect(rows.map(\.exerciseName) == ["Bench"])
        #expect(rows[0].supersetGroup == nil)
        let sets = (rows[0].sets ?? []).sorted { $0.position < $1.position }
        #expect(sets.count == 2)
        #expect(sets.map(\.position) == [0, 1])
        #expect(sets[1].id == new)
        #expect(sets.allSatisfy { $0.completed })
        let setCount = try context.fetchCount(FetchDescriptor<WorkoutSet>())
        let rowCount = try context.fetchCount(FetchDescriptor<WorkoutExercise>())
        #expect(setCount == 2)
        #expect(rowCount == 1)
    }

    @Test func saveReordersExercises() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let model = workout(context)
        var draft = PastWorkoutDraft(model)
        draft.reorder(draft.exercises.map(\.id).reversed())
        try draft.save(to: model, in: context)
        let names = (model.exercises ?? []).sorted { $0.position < $1.position }.map(\.exerciseName)
        #expect(names == ["Row", "Bench"])
    }
}
