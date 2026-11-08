import CoreData
import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

/// Review C-11 (b) and (c): what the app does once CloudKit merges another device's changes in.
@Suite struct CloudKitReadinessTests {
    typealias Rig = EngineTests.Rig
    private let t0 = TestSupport.referenceDate

    private func candidate(_ started: Double, completed: [Double?] = [], id: UUID = UUID())
        -> InProgressResolution.Candidate
    {
        InProgressResolution.Candidate(
            id: id,
            startedAt: t0.addingTimeInterval(started),
            completedSets: completed.map { $0.map { t0.addingTimeInterval($0) } }
        )
    }

    // MARK: InProgressResolution

    @Test func noCandidatesKeepsNothing() {
        #expect(InProgressResolution.plan(for: []) == .init(keep: nil, settled: []))
    }

    @Test func oneCandidateIsKept() {
        let only = candidate(0)
        #expect(InProgressResolution.plan(for: [only]) == .init(keep: only.id, settled: []))
    }

    @Test func newestStartIsKeptAndOlderOnesAreSettled() {
        let oldest = candidate(0)
        let middle = candidate(100, completed: [150, 400])
        let newest = candidate(200, completed: [250])
        let plan = InProgressResolution.plan(for: [middle, newest, oldest])
        #expect(plan.keep == newest.id)
        #expect(
            plan.settled == [
                .init(id: middle.id, action: .finish(at: t0.addingTimeInterval(400))),
                .init(id: oldest.id, action: .delete),
            ]
        )
    }

    @Test func startTieIsBrokenByIdSoEveryDevicePicksTheSame() {
        let low = candidate(0, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID())
        let high = candidate(0, id: UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID())
        #expect(InProgressResolution.plan(for: [low, high]).keep == high.id)
        #expect(InProgressResolution.plan(for: [high, low]).keep == high.id)
    }

    @Test func completedSetWithoutTimeFinishesAtStartAndEndNeverPrecedesStart() {
        #expect(
            InProgressResolution.action(for: candidate(10, completed: [nil])) == .finish(at: t0.addingTimeInterval(10))
        )
        #expect(
            InProgressResolution.action(for: candidate(10, completed: [5])) == .finish(at: t0.addingTimeInterval(10))
        )
        #expect(InProgressResolution.action(for: candidate(10)) == .delete)
    }

    // MARK: resume() settles the older in-progress workouts

    @Test func resumeKeepsTheNewestAndFinishesOrDeletesTheOlderOnes() throws {
        let rig = try Rig()
        let context = rig.context
        // Older with a logged set (and an unchecked one that must be dropped).
        let logged = makeWorkout(in: context, name: "Logged", startedAt: t0, minutes: nil)
        let row = WorkoutExercise(exerciseID: LibraryFixture.squat, exerciseName: "Back Squat", unit: .kg)
        context.insert(row)
        row.workout = logged
        let done = WorkoutSet(
            position: 0,
            weight: 100,
            reps: 5,
            completed: true,
            completedAt: t0.addingTimeInterval(600)
        )
        let open = WorkoutSet(position: 1)
        for set in [done, open] {
            context.insert(set)
            set.workoutExercise = row
        }
        makeWorkout(in: context, name: "Empty", startedAt: t0.addingTimeInterval(100), minutes: nil)
        let newest = makeWorkout(in: context, name: "Newest", startedAt: t0.addingTimeInterval(200), minutes: nil)
        try context.save()

        let engine = try rig.makeEngine()
        #expect(engine.workout?.id == newest.id)
        let inProgress = try context.fetch(FetchDescriptor<Workout>(predicate: Workout.inProgressPredicate))
        #expect(inProgress.map(\.id) == [newest.id])
        #expect(logged.finishedAt == t0.addingTimeInterval(600))
        #expect((logged.exercises ?? []).flatMap { $0.sets ?? [] }.map(\.position) == [0])
        let names = try context.fetch(FetchDescriptor<Workout>()).map(\.name).sorted()
        #expect(names == ["Logged", "Newest"])
    }

    @Test func resumeLeavesASingleInProgressWorkoutAlone() throws {
        let rig = try Rig()
        let only = makeWorkout(in: rig.context, name: "Only", startedAt: t0, minutes: nil)
        try rig.context.save()
        let engine = try rig.makeEngine()
        #expect(engine.workout?.id == only.id)
        #expect(only.finishedAt == nil)
    }

    // MARK: Reloads after a remote change

    @Test func exerciseStoreReloadsCustomExercisesFromTheContext() throws {
        let rig = try Rig()
        let remote = Exercise(name: "Sled Push", weightType: .weighted)
        #expect(rig.store.exercise(id: remote.id) == nil)
        rig.context.insert(remote)
        try rig.context.save()
        try rig.store.reloadCustom(from: rig.context)
        #expect(rig.store.exercise(id: remote.id)?.name == "Sled Push")
        rig.context.delete(remote)
        try rig.context.save()
        try rig.store.reloadCustom(from: rig.context)
        #expect(rig.store.exercise(id: remote.id) == nil)
    }

    @Test func engineReloadsPreviousValuesForTheRunningWorkout() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        let running = try engine.startEmpty()
        let row = WorkoutExercise(exerciseID: LibraryFixture.squat, exerciseName: "Back Squat", unit: .kg)
        rig.context.insert(row)
        row.workout = running
        let set = WorkoutSet(position: 0)
        rig.context.insert(set)
        set.workoutExercise = row
        try rig.context.save()
        try engine.reloadPrevious()
        #expect(engine.previous(for: set) == nil)

        // A workout finished on another device arrives through the mirror.
        rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(weight: 90, reps: 5, kind: .normal)],
            startedAt: t0.addingTimeInterval(-86400)
        )
        try rig.context.save()
        #expect(engine.previous(for: set) == nil)
        try engine.reloadPrevious()
        #expect(engine.previous(for: set)?.weight == 90)
        #expect(engine.workout?.id == running.id)
    }

    @Test func reloadPreviousWithNoWorkoutIsANoOp() throws {
        let rig = try Rig()
        let engine = try rig.makeEngine()
        try engine.reloadPrevious()
        #expect(engine.workout == nil)
    }

    // MARK: RemoteChangeObserver

    @Test func observerRunsOnceAfterABurstAndStopsWhenAsked() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("test.remoteChange")
        var calls = 0
        let signal = CallSignal()
        // The debounce runs on a manual clock, so "nothing more happens" is structural: no sleeper left, no task armed.
        let clock = ManualClock()
        let debounce = Duration.milliseconds(100)
        let observer = RemoteChangeObserver(center: center, name: name, debounce: debounce, clock: clock) {
            calls += 1
            signal.fire()
        }
        observer.start()
        observer.start()
        for _ in 0..<5 { center.post(name: name, object: nil) }
        // The whole burst is in (each notification hops to the main actor) and one wait is armed.
        #expect(try await eventually { observer.scheduleCount == 5 }, "the burst never reached the observer")
        #expect(try await eventually { clock.sleeperCount == 1 })
        #expect(calls == 0)
        clock.advance(by: debounce)
        #expect(await signal.wait(), "the burst never reached the handler")
        // A burst is one call, however long time runs on afterwards.
        clock.advance(by: debounce * 3)
        for _ in 0..<20 { await Task.yield() }
        #expect(calls == 1)
        #expect(clock.sleeperCount == 0)

        center.post(name: name, object: nil)
        #expect(try await eventually { observer.scheduleCount == 6 })
        #expect(try await eventually { clock.sleeperCount == 1 })
        clock.advance(by: debounce)
        #expect(await signal.wait(), "the later change never reached the handler")
        #expect(calls == 2)

        // Stopping drops the wait that is armed and holds nothing, whatever the clock does.
        center.post(name: name, object: nil)
        #expect(try await eventually { observer.scheduleCount == 7 })
        #expect(try await eventually { clock.sleeperCount == 1 })
        observer.stop()
        #expect(!observer.isScheduled)
        #expect(try await eventually { clock.sleeperCount == 0 }, "stop() left a wait armed")
        clock.advance(by: debounce * 3)
        for _ in 0..<20 { await Task.yield() }
        #expect(calls == 2)
        // A notification after stop() is not even heard.
        center.post(name: name, object: nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(observer.scheduleCount == 7)
        #expect(!observer.isScheduled)
        #expect(clock.sleeperCount == 0)
        #expect(calls == 2)
    }

    @Test func observerListensToThePersistentStoreRemoteChangeNotificationByDefault() async throws {
        let center = NotificationCenter()
        var calls = 0
        let signal = CallSignal()
        let observer = RemoteChangeObserver(center: center, debounce: .milliseconds(20)) {
            calls += 1
            signal.fire()
        }
        observer.start()
        center.post(name: .NSPersistentStoreRemoteChange, object: nil)
        #expect(await signal.wait(), "the default notification never reached the handler")
        #expect(calls == 1)
        observer.stop()
    }
}
