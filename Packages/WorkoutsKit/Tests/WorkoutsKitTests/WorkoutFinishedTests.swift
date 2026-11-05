import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct WorkoutFinishedTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func seeded() throws -> (ModelContext, finished: Workout, old: Workout, running: Workout) {
        let context = ModelContext(try ModelContainer.workouts(inMemory: true, cloudKit: false))
        let old = Workout(name: "Old", startedAt: t0, finishedAt: t0.addingTimeInterval(3_600))
        let finished = Workout(
            name: "Done",
            startedAt: t0.addingTimeInterval(86_400),
            finishedAt: t0.addingTimeInterval(86_400 + 3_600)
        )
        let running = Workout(name: "Running", startedAt: t0.addingTimeInterval(172_800))
        for workout in [old, finished, running] { context.insert(workout) }
        try context.save()
        return (context, finished, old, running)
    }

    @Test func isFinishedFollowsFinishedAt() throws {
        let (_, finished, _, running) = try seeded()
        #expect(finished.isFinished)
        #expect(!running.isFinished)
    }

    @Test func finishedPredicateSkipsTheRunningWorkout() throws {
        let (context, _, _, _) = try seeded()
        let names = try context.fetch(FetchDescriptor<Workout>(predicate: Workout.finishedPredicate)).map(\.name)
        #expect(Set(names) == ["Old", "Done"])
        #expect(try context.fetch(Workout.allFinished).count == 2)
    }

    @Test func finishedPredicateByIDMatchesOnlyAFinishedWorkout() throws {
        let (context, finished, _, running) = try seeded()
        let hit = try context.fetch(FetchDescriptor<Workout>(predicate: Workout.finishedPredicate(id: finished.id)))
        #expect(hit.map(\.name) == ["Done"])
        let miss = try context.fetch(FetchDescriptor<Workout>(predicate: Workout.finishedPredicate(id: running.id)))
        #expect(miss.isEmpty)
        #expect(try context.fetch(Workout.finished(id: finished.id)).map(\.name) == ["Done"])
        #expect(try context.fetch(Workout.finished(id: running.id)).isEmpty)
    }

    @Test func finishedPredicateExcludingLeavesOutThatWorkoutAndTheRunningOne() throws {
        let (context, finished, _, _) = try seeded()
        let rest = try context.fetch(
            FetchDescriptor<Workout>(predicate: Workout.finishedPredicate(excluding: finished.id))
        )
        #expect(rest.map(\.name) == ["Old"])
    }

    @Test func finishedPredicateSinceKeepsRecentFinishesOnly() throws {
        let (context, _, _, _) = try seeded()
        let cutoff = t0.addingTimeInterval(43_200)
        let recent = try context.fetch(FetchDescriptor<Workout>(predicate: Workout.finishedPredicate(since: cutoff)))
        #expect(recent.map(\.name) == ["Done"])
    }

    @Test func inProgressIsTheUnfinishedWorkout() throws {
        let (context, _, _, running) = try seeded()
        #expect(try context.fetch(Workout.inProgress).map(\.id) == [running.id])
        let names = try context.fetch(FetchDescriptor<Workout>(predicate: Workout.inProgressPredicate)).map(\.name)
        #expect(names == ["Running"])
    }
}
