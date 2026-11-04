import ActivityKit
import Foundation
import SwiftData
import Testing
import WorkoutsKit

@testable import Workouts

@MainActor
final class FakeLiveActivity: LiveActivityHandle {
    let id = UUID().uuidString
    let workoutID: UUID
    var contents: [ActivityContent<WorkoutActivityState>]
    var endedWith: ActivityUIDismissalPolicy?

    init(workoutID: UUID, content: ActivityContent<WorkoutActivityState>? = nil) {
        self.workoutID = workoutID
        self.contents = content.map { [$0] } ?? []
    }

    var isEnded: Bool { endedWith != nil }

    func update(_ content: ActivityContent<WorkoutActivityState>) async { contents.append(content) }

    func end(dismissalPolicy: ActivityUIDismissalPolicy) async { endedWith = dismissalPolicy }
}

@MainActor
final class FakeLiveActivityProvider: LiveActivityProviding {
    var activities: [FakeLiveActivity] = []
    var requested: [FakeLiveActivity] = []
    var failure: (any Error)?

    var existing: [any LiveActivityHandle] { activities.filter { !$0.isEnded } }

    func request(
        workoutID: UUID,
        content: ActivityContent<WorkoutActivityState>
    ) throws -> any LiveActivityHandle {
        if let failure { throw failure }
        let activity = FakeLiveActivity(workoutID: workoutID, content: content)
        activities.append(activity)
        requested.append(activity)
        return activity
    }
}

@MainActor
@Suite struct LiveActivityControllerTests {
    final class Clock {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
    }

    let provider = FakeLiveActivityProvider()
    let clock = Clock()
    let container: ModelContainer
    let engine: ActiveWorkoutEngine
    let controller: LiveActivityController

    init() throws {
        container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        let clock = clock
        engine = try ActiveWorkoutEngine(
            context: container.mainContext,
            store: ExerciseStore(catalog: try LibraryCatalog.bundled(in: .main)),
            settings: SettingsStore(backend: InMemoryBackend()),
            now: { clock.date }
        )
        controller = LiveActivityController(provider: provider)
        controller.attach(engine)
    }

    @Test func nothingRequestedWithoutAWorkout() async {
        await controller.reconcile()
        #expect(provider.requested.isEmpty)
    }

    @Test func requestsOnceWhenAWorkoutAppears() async throws {
        let workout = try engine.startEmpty()
        await controller.reconcile()
        await controller.reconcile()
        let activity = try #require(provider.requested.first)
        #expect(provider.requested.count == 1)
        #expect(activity.workoutID == workout.id)
        #expect(activity.contents.count == 1)
        let content = try #require(activity.contents.first)
        #expect(content.state == engine.activityState)
        #expect(content.staleDate == nil)
        #expect(content.relevanceScore == 0)
    }

    @Test func updatesWhenTheRestStartsAndAdjusts() async throws {
        try engine.startEmpty()
        await controller.reconcile()
        let activity = try #require(provider.requested.first)

        try engine.startRest(seconds: 90)
        await controller.reconcile()
        #expect(activity.contents.count == 2)
        let resting = try #require(activity.contents.last)
        #expect(resting.staleDate == clock.date.addingTimeInterval(90))
        #expect(resting.relevanceScore == 1)
        #expect(resting.state.isResting)

        try engine.adjustRest(by: 30)
        await controller.reconcile()
        #expect(activity.contents.count == 3)
        #expect(activity.contents.last?.staleDate == clock.date.addingTimeInterval(120))

        try engine.skipRest()
        await controller.reconcile()
        #expect(activity.contents.count == 4)
        #expect(activity.contents.last?.state.isResting == false)
        #expect(activity.contents.last?.staleDate == nil)
        #expect(activity.contents.last?.relevanceScore == 0)
        #expect(provider.requested.count == 1)
    }

    @Test func unchangedStateDoesNotUpdate() async throws {
        try engine.startEmpty()
        await controller.reconcile()
        await controller.reconcile()
        #expect(provider.requested.first?.contents.count == 1)
    }

    @Test func discardEndsImmediately() async throws {
        try engine.startEmpty()
        await controller.reconcile()
        let activity = try #require(provider.requested.first)

        try engine.discard()
        await controller.reconcile()
        #expect(activity.endedWith == .immediate)

        // A new workout gets a new activity.
        try engine.startEmpty()
        await controller.reconcile()
        #expect(provider.requested.count == 2)
    }

    @Test func adoptsAnExistingActivityOfTheSameWorkout() async throws {
        let workout = try engine.startEmpty()
        let leftover = FakeLiveActivity(workoutID: workout.id)
        provider.activities = [leftover]

        await controller.reconcile()
        #expect(provider.requested.isEmpty)
        #expect(!leftover.isEnded)
        #expect(leftover.contents.count == 1)

        try engine.startRest(seconds: 60)
        await controller.reconcile()
        #expect(leftover.contents.count == 2)
        #expect(provider.requested.isEmpty)
    }

    @Test func endsOrphanedActivities() async throws {
        let workout = try engine.startEmpty()
        let orphan = FakeLiveActivity(workoutID: UUID())
        let duplicate = FakeLiveActivity(workoutID: workout.id)
        let mine = FakeLiveActivity(workoutID: workout.id)
        provider.activities = [orphan, mine, duplicate]

        await controller.reconcile()
        #expect(orphan.endedWith == .immediate)
        #expect(duplicate.endedWith == .immediate)
        #expect(!mine.isEnded)
        #expect(provider.requested.isEmpty)
    }

    @Test func endsAllWhenThereIsNoWorkoutAtLaunch() async {
        let orphan = FakeLiveActivity(workoutID: UUID())
        provider.activities = [orphan]
        await controller.reconcile()
        #expect(orphan.endedWith == .immediate)
    }

    @Test func aFailedRequestIsRetriedOnTheNextChange() async throws {
        struct Refused: Error {}
        provider.failure = Refused()
        try engine.startEmpty()
        await controller.reconcile()
        #expect(provider.requested.isEmpty)

        provider.failure = nil
        await controller.reconcile()
        #expect(provider.requested.count == 1)
    }

    @Test func contentUsesTheRestEndAsStaleDate() {
        let end = clock.date.addingTimeInterval(45)
        let resting = LiveActivityController.content(
            for: WorkoutActivityState(workoutName: "Push", startedAt: clock.date, restEndsAt: end, restTotal: 45)
        )
        #expect(resting.staleDate == end)
        #expect(resting.relevanceScore == 1)
        let idle = LiveActivityController.content(for: WorkoutActivityState(workoutName: "Push", startedAt: clock.date))
        #expect(idle.staleDate == nil)
        #expect(idle.relevanceScore == 0)
    }
}
