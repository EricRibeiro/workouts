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
    /// What ActivityKit reports; tests set `.ended` (system) or `.dismissed` (swiped away).
    var activityState: ActivityState = .active

    init(workoutID: UUID, content: ActivityContent<WorkoutActivityState>? = nil) {
        self.workoutID = workoutID
        self.contents = content.map { [$0] } ?? []
    }

    var isEnded: Bool { endedWith != nil }

    /// When set, `update` suspends until ``releaseUpdate()``, like ActivityKit taking its time.
    var holdsUpdates = false
    private var held: CheckedContinuation<Void, Never>?

    func update(_ content: ActivityContent<WorkoutActivityState>) async {
        if holdsUpdates { await withCheckedContinuation { held = $0 } }
        contents.append(content)
    }

    func releaseUpdate() {
        held?.resume()
        held = nil
    }

    func end(dismissalPolicy: ActivityUIDismissalPolicy) async { endedWith = dismissalPolicy }
}

@MainActor
final class FakeLiveActivityProvider: LiveActivityProviding {
    var activities: [FakeLiveActivity] = []
    var requested: [FakeLiveActivity] = []
    var failure: (any Error)?
    var areActivitiesEnabled = true
    var requestAttempts = 0

    struct Unexpected: Error {}

    var existing: [any LiveActivityHandle] { activities.filter { !$0.isEnded } }

    func existingActivities() async -> [any LiveActivityHandle] { existing }

    func activitiesEnabled() async -> Bool { areActivitiesEnabled }

    func request(
        workoutID: UUID,
        content: ActivityContent<WorkoutActivityState>
    ) async throws -> any LiveActivityHandle {
        requestAttempts += 1
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

    @Test func aSecondObserveAndConcurrentReconcilesWhileOneRunsRequestNoSecondActivity() async throws {
        let workout = try engine.startEmpty()
        controller.observe(engine)
        controller.observe(engine)
        async let first: Void = controller.reconcile()
        async let second: Void = controller.reconcile()
        _ = await (first, second)
        await controller.syncNow()

        #expect(provider.requestAttempts == 1)
        #expect(provider.requested.count == 1)
        #expect(provider.existing.count == 1)
        #expect(provider.requested.first?.workoutID == workout.id)
        #expect(provider.requested.first?.isEnded == false)
    }

    @Test func aWorkoutStartedAfterAFinishedOneGetsItsOwnActivityAndTheOldOneStaysEnded() async throws {
        let firstWorkout = try engine.startEmpty()
        await controller.reconcile()
        let first = try #require(provider.requested.first)
        try engine.discard()
        await controller.reconcile()
        #expect(first.endedWith == .immediate)

        let secondWorkout = try engine.startEmpty()
        #expect(secondWorkout.id != firstWorkout.id)
        await controller.reconcile()
        #expect(provider.requested.count == 2)
        let second = try #require(provider.requested.last)
        #expect(second.workoutID == secondWorkout.id)
        // Only the new one is live, and it opens with the new workout's state, not the old one's.
        #expect(provider.existing.count == 1)
        #expect(second.isEnded == false)
        #expect(second.contents.count == 1)
        #expect(second.contents.first?.state == engine.activityState)
        #expect(first.contents.count == 1)
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

    // MARK: System-ended and dismissed activities

    @Test func requestsANewActivityWhenTheSystemEndedTheHeldOne() async throws {
        try engine.startEmpty()
        await controller.reconcile()
        let first = try #require(provider.requested.first)

        first.activityState = .ended
        try engine.startRest(seconds: 60)
        await controller.reconcile()

        #expect(provider.requested.count == 2)
        let second = try #require(provider.requested.last)
        #expect(second !== first)
        #expect(first.contents.count == 1)  // nothing sent to the dead one
        #expect(second.contents.last?.state == engine.activityState)

        // The new one keeps getting the updates.
        try engine.adjustRest(by: 30)
        await controller.reconcile()
        #expect(second.contents.count == 2)
        #expect(provider.requested.count == 2)
    }

    @Test func doesNotRequestAgainAfterThePersonDismissedIt() async throws {
        try engine.startEmpty()
        await controller.reconcile()
        let first = try #require(provider.requested.first)

        first.activityState = .dismissed
        try engine.startRest(seconds: 60)
        await controller.reconcile()
        try engine.adjustRest(by: 30)
        await controller.reconcile()
        #expect(provider.requested.count == 1)
        #expect(first.contents.count == 1)

        // A later workout starts fresh.
        try engine.discard()
        await controller.reconcile()
        try engine.startEmpty()
        await controller.reconcile()
        #expect(provider.requested.count == 2)
    }

    @Test func doesNotAdoptLeftoversThatAreNoLongerLive() async throws {
        let workout = try engine.startEmpty()
        let ended = FakeLiveActivity(workoutID: workout.id)
        ended.activityState = .ended
        provider.activities = [ended]
        await controller.reconcile()
        #expect(ended.contents.isEmpty)
        #expect(provider.requested.count == 1)
        #expect(provider.requested.first?.workoutID == workout.id)
    }

    @Test func aStaleLeftoverIsAdopted() async throws {
        let workout = try engine.startEmpty()
        let stale = FakeLiveActivity(workoutID: workout.id)
        stale.activityState = .stale
        provider.activities = [stale]
        await controller.reconcile()
        #expect(provider.requested.isEmpty)
        #expect(stale.contents.count == 1)
    }

    @Test func aDismissedLeftoverIsNotReplaced() async throws {
        let workout = try engine.startEmpty()
        let dismissed = FakeLiveActivity(workoutID: workout.id)
        dismissed.activityState = .dismissed
        provider.activities = [dismissed]
        await controller.reconcile()
        await controller.reconcile()
        #expect(provider.requested.isEmpty)
        #expect(dismissed.contents.isEmpty)
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

    @Test func nothingIsRequestedWhileActivitiesAreOffAndItStartsWhenTheyTurnOn() async throws {
        provider.areActivitiesEnabled = false
        provider.failure = FakeLiveActivityProvider.Unexpected()  // a request while off would throw
        try engine.startEmpty()
        await controller.reconcile()
        await controller.reconcile()
        #expect(provider.requested.isEmpty)
        #expect(provider.requestAttempts == 0)

        provider.areActivitiesEnabled = true
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

    // MARK: Syncing now

    @Test func syncNowBypassesTheDebounceAndReturnsAfterTheUpdate() async throws {
        let debounced = LiveActivityController(provider: provider, debounce: .seconds(60))
        try engine.startEmpty()
        debounced.observe(engine)
        await debounced.syncNow()
        let activity = try #require(provider.requested.first)
        try engine.startRest(seconds: 60)
        #expect(activity.contents.count == 1)

        await debounced.syncNow()

        #expect(activity.contents.count == 2)
        #expect(activity.contents.last?.state == engine.activityState)
    }

    /// A run already in flight must not make the caller return early: the caller's own change rides its extra pass.
    @Test func syncNowDuringARunWaitsForTheExtraPass() async throws {
        let debounced = LiveActivityController(provider: provider, debounce: .seconds(60))
        try engine.startEmpty()
        debounced.observe(engine)
        await debounced.syncNow()
        let activity = try #require(provider.requested.first)
        try engine.startRest(seconds: 60)
        activity.holdsUpdates = true
        let first = Task { await debounced.reconcile() }
        for _ in 0..<5 { await Task.yield() }  // the first run is now suspended inside update

        try engine.adjustRest(by: 30)
        var returned = false
        let second = Task {
            await debounced.syncNow()
            returned = true
        }
        for _ in 0..<5 { await Task.yield() }
        #expect(!returned)

        activity.holdsUpdates = false
        activity.releaseUpdate()
        await first.value
        await second.value

        #expect(returned)
        #expect(activity.contents.last?.state == engine.activityState)
        #expect(activity.contents.last?.staleDate == clock.date.addingTimeInterval(90))
    }

    // MARK: Coalescing

    @Test func aBurstOfChangesUpdatesOnceWithTheFinalState() async throws {
        let debounced = LiveActivityController(provider: provider, debounce: .milliseconds(80))
        try engine.startEmpty()
        debounced.observe(engine)
        try await Task.sleep(for: .milliseconds(300))
        let activity = try #require(provider.requested.first)
        #expect(activity.contents.count == 1)

        try engine.startRest(seconds: 60)
        for _ in 0..<5 { try engine.adjustRest(by: 30) }
        // Inside the window nothing has been sent yet.
        #expect(activity.contents.count == 1)

        try await Task.sleep(for: .milliseconds(400))
        #expect(activity.contents.count == 2)
        #expect(activity.contents.last?.staleDate == clock.date.addingTimeInterval(210))
        #expect(activity.contents.last?.state == engine.activityState)

        // A change after the window is its own update.
        try engine.adjustRest(by: 30)
        try await Task.sleep(for: .milliseconds(400))
        #expect(activity.contents.count == 3)
        #expect(activity.contents.last?.staleDate == clock.date.addingTimeInterval(240))
    }
}
