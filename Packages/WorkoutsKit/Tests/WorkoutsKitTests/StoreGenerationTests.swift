import Foundation
import SwiftData
import Synchronization
import Testing

@testable import WorkoutsKit

@Suite struct StoreGenerationTests {
    @Test func startsAtZeroAndBumpsByOne() {
        let generation = StoreGeneration()
        #expect(generation.value == 0)
        generation.bump()
        generation.bump()
        #expect(generation.value == 2)
    }

    @Test func bumpIsObservable() {
        let generation = StoreGeneration()
        let changes = Atomic(0)
        withObservationTracking {
            _ = generation.value
        } onChange: {
            changes.add(1, ordering: .relaxed)
        }
        generation.bump()
        #expect(changes.load(ordering: .relaxed) == 1)
    }

    /// The C-04 case: an import rewrites an older workout. The newest `updatedAt` stays as it was, so only the
    /// generation tells the caches to re-derive.
    @Test func stampChangesWhenAnOlderWorkoutIsUpdated() throws {
        let context = try makeTestContext()
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let older = Workout(name: "Old", startedAt: t0, finishedAt: t0, updatedAt: t0)
        let newer = Workout(
            name: "New",
            startedAt: t0.addingTimeInterval(86_400),
            finishedAt: t0.addingTimeInterval(86_400),
            updatedAt: t0.addingTimeInterval(86_400)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()
        let generation = StoreGeneration()

        func stamp() throws -> FinishedWorkoutsStamp {
            let newest = try context.fetch(Workout.newestFinishedEdit).first?.updatedAt
            return FinishedWorkoutsStamp(newestEdit: newest, generation: generation.value)
        }
        let before = try stamp()
        #expect(before.newestEdit == newer.updatedAt)

        // The import brings a correction for the older workout: its stamp is newer than its own, older than `newer`'s.
        older.name = "Old, corrected"
        older.updatedAt = t0.addingTimeInterval(3_600)
        try context.save()
        #expect(try stamp() == before, "the newest updatedAt cannot see this edit")

        generation.bump()
        #expect(try stamp() != before)
    }

    @Test func finishedDescriptorsSelectOnlyFinishedWorkouts() throws {
        let context = try makeTestContext()
        let done = Workout(name: "Done", startedAt: .now, finishedAt: .now)
        let running = Workout(name: "Running", startedAt: .now)
        context.insert(done)
        context.insert(running)
        try context.save()
        #expect(try context.fetch(Workout.allFinished).map(\.id) == [done.id])
        #expect(try context.fetch(Workout.finished(id: done.id)).map(\.id) == [done.id])
        #expect(try context.fetch(Workout.finished(id: running.id)).isEmpty)
        #expect(try context.fetch(Workout.newestFinishedEdit).map(\.id) == [done.id])
    }
}
