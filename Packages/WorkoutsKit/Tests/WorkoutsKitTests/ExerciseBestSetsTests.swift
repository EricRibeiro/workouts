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
        #expect(ExerciseBestSets.text(for: plank, options: kg) == "0:45")
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
        let container = try makeTestContainer()
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

    @MainActor
    @Test func sessionsFromFetchedRowsEqualTheFullWalk() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let other = UUID()
        // Inserted out of date order, with another exercise, an unfinished workout, a repeated row and unsorted sets.
        for (index, day) in [5, 1, 9, 3, 7].enumerated() {
            let start = Date(timeIntervalSince1970: Double(day) * 86_400)
            let finished: Date? = day == 7 ? nil : start.addingTimeInterval(3_600)
            let workout = Workout(name: "Day \(day)", startedAt: start, finishedAt: finished)
            context.insert(workout)
            let ids = day == 3 ? [exercise, other, exercise] : [exercise, other]
            for (position, id) in ids.enumerated() {
                let row = WorkoutExercise(
                    exerciseID: id,
                    position: position,
                    unit: index.isMultiple(of: 2) ? .kg : .lb,
                    workout: workout
                )
                _ = WorkoutSet(position: 2, kind: .warmup, weight: 40, reps: 8, completed: true, workoutExercise: row)
                _ = WorkoutSet(position: 1, weight: Double(60 + day), reps: 5, completed: true, workoutExercise: row)
                _ = WorkoutSet(position: 0, weight: 200, reps: 1, completed: false, workoutExercise: row)
            }
        }
        // A row whose workout was never set must not appear either.
        context.insert(WorkoutExercise(exerciseID: exercise))
        try context.save()

        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let walked = try #require(ExerciseBestSets.sessions(from: workouts, weightType: { _ in .barbell })[exercise])
        let rows = try context.fetch(ExerciseBestSets.rowsDescriptor(exerciseID: exercise))
        let fetched = ExerciseBestSets.sessions(forRows: rows, weightType: .barbell)

        #expect(rows.count == 5)
        #expect(fetched.count == walked.count)
        #expect(fetched.map(\.time) == fetched.map(\.time).sorted())
        // Same sessions, compared irrespective of the walk's own order (the walk keeps the store's order).
        let key: (Session) -> [Double] = { [$0.time.timeIntervalSince1970, Double($0.sets.count)] }
        #expect(fetched.map(key) == walked.sorted { $0.time < $1.time }.map(key))
        #expect(Set(fetched) == Set(walked))
        #expect(
            ExerciseBestSets.workoutNames(of: rows)
                == Dictionary(uniqueKeysWithValues: workouts.filter { $0.finishedAt != nil }.map { ($0.id, $0.name) })
        )
    }
}
