import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

struct ExerciseBestSetsTests {
    let exercise = UUID()
    let kg = RecordsOptions()

    func session(daysAgo: Int, type: WeightType = .barbell, _ sets: [LoggedSet]) -> Session {
        Session(
            workoutID: UUID(),
            time: Date(timeIntervalSince1970: 1_000_000 - Double(daysAgo) * 86_400),
            exerciseID: exercise,
            weightType: type,
            sets: sets
        )
    }

    @Test func usesTheNewestSessionNotTheAllTimeBest() {
        let sessions = [
            session(daysAgo: 10, [LoggedSet(weight: 120, reps: 5)]),
            session(daysAgo: 1, [LoggedSet(weight: 100, reps: 5), LoggedSet(kind: .warmup, weight: 150, reps: 5)]),
        ]
        #expect(ExerciseBestSets.text(for: sessions, options: kg) == "100 kg × 5")
    }

    @Test func skipsNewestSessionWithoutCountedSets() {
        let sessions = [
            session(daysAgo: 5, [LoggedSet(weight: 80, reps: 8)]),
            session(daysAgo: 1, [LoggedSet(weight: 100, reps: 5, completed: false)]),
        ]
        #expect(ExerciseBestSets.text(for: sessions, options: kg) == "80 kg × 8")
    }

    @Test func formatsInTheDisplayUnitBodyweightAndTimed() {
        let lb = RecordsOptions(displayUnit: .lb)
        let heavy = [session(daysAgo: 1, [LoggedSet(weight: 100, unit: .kg, reps: 5)])]
        #expect(ExerciseBestSets.text(for: heavy, options: lb) == "220.5 lb × 5")
        let bodyweight = [session(daysAgo: 1, type: .bodyweight, [LoggedSet(reps: 12)])]
        #expect(ExerciseBestSets.text(for: bodyweight, options: kg) == "12 reps")
        let plank = [session(daysAgo: 1, type: .unweighted, [LoggedSet(durationSeconds: 45)])]
        #expect(ExerciseBestSets.text(for: plank, options: kg) == "45 s")
    }

    @Test func neverPerformedIsEmptyAndLeftOutOfTheMap() {
        #expect(ExerciseBestSets.text(for: [], options: kg) == "")
        let map = ExerciseBestSets.texts(
            from: [exercise: [session(daysAgo: 1, [LoggedSet(weight: 50, reps: 10)])], UUID(): []],
            options: kg
        )
        #expect(map == [exercise: "50 kg × 10"])
    }

    @MainActor
    @Test func sessionsFromWorkoutsKeepFinishedCompletedSetsOnly() throws {
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        let context = container.mainContext
        let done = Workout(startedAt: Date(timeIntervalSince1970: 500), finishedAt: Date(timeIntervalSince1970: 900))
        let open = Workout(startedAt: Date(timeIntervalSince1970: 600))
        for workout in [done, open] {
            let row = WorkoutExercise(exerciseID: exercise, unit: .kg, workout: workout)
            _ = WorkoutSet(position: 1, weight: 60, reps: 5, completed: true, workoutExercise: row)
            _ = WorkoutSet(position: 0, weight: 100, reps: 3, completed: false, workoutExercise: row)
            context.insert(workout)
        }
        let sessions = ExerciseBestSets.sessions(from: [done, open], weightType: { _ in .barbell })
        let found = try #require(sessions[exercise])
        #expect(found.count == 1)
        #expect(found[0].sets.count == 1)
        #expect(ExerciseBestSets.text(for: found, options: kg) == "60 kg × 5")
    }
}
