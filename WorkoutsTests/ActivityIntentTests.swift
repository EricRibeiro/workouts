import ActivityKit
import Foundation
import SwiftData
import Testing
import UserNotifications
import WorkoutsKit

@testable import Workouts

/// The Live Activity buttons end to end in-process: the real intents, `ActivityIntentRouter` and
/// `EngineActivityIntentHandler` over a real in-memory engine. Serialized because the router's handler is static.
@MainActor
@Suite(.serialized)
final class ActivityIntentTests {
    final class Clock {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
    }

    let clock = Clock()
    let container: ModelContainer
    let store: ExerciseStore
    let engine: ActiveWorkoutEngine
    init() throws {
        container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        store = ExerciseStore(catalog: try LibraryCatalog.bundled(in: .main))
        let clock = clock
        engine = try ActiveWorkoutEngine(
            context: container.mainContext,
            store: store,
            settings: SettingsStore(backend: InMemoryBackend()),
            now: { clock.date }
        )
        ActivityIntentRouter.handler = EngineActivityIntentHandler(engine: engine)
    }

    deinit {
        MainActor.assumeIsolated { ActivityIntentRouter.handler = nil }
    }

    private func makeEngine() throws -> ActiveWorkoutEngine {
        let clock = clock
        return try ActiveWorkoutEngine(
            context: container.mainContext,
            store: store,
            settings: SettingsStore(backend: InMemoryBackend()),
            now: { clock.date }
        )
    }

    /// Starts a workout on `engine` with one exercise whose first set has values typed in (so it can be checked).
    @discardableResult
    private func startWorkout(on engine: ActiveWorkoutEngine) throws -> [WorkoutSet] {
        try engine.startEmpty()
        let info = try #require(store.search("squat").first)
        let row = try engine.addExercise(info)
        let sets = (row.sets ?? []).sorted { $0.position < $1.position }
        try engine.setValues(try #require(sets.first), weight: 100, reps: 5, durationSeconds: nil)
        return sets
    }

    // MARK: Skip / +30

    @Test func skipEndsARunningRest() async throws {
        try startWorkout(on: engine)
        try engine.startRest(seconds: 90)
        #expect(engine.restTimer.isActive)

        try await SkipRestIntent().perform()

        #expect(!engine.restTimer.isActive)
        #expect(engine.workout?.restEndsAt == nil)
    }

    @Test func addThirtyExtendsTheRest() async throws {
        try startWorkout(on: engine)
        try engine.startRest(seconds: 90)
        let end = try #require(engine.restTimer.endsAt)

        try await AddRestIntent(seconds: 30).perform()

        #expect(engine.restTimer.endsAt == end.addingTimeInterval(30))
        #expect(engine.restTimer.total == 120)
    }

    @Test func addRestDefaultsToThirty() async throws {
        try startWorkout(on: engine)
        try engine.startRest(seconds: 60)
        try await AddRestIntent().perform()
        #expect(engine.restTimer.total == 90)
    }

    @Test func addingAnUnsupportedAmountChangesNothing() async throws {
        try startWorkout(on: engine)
        try engine.startRest(seconds: 60)
        let end = engine.restTimer.endsAt

        try await AddRestIntent(seconds: 45).perform()

        #expect(engine.restTimer.endsAt == end)
        #expect(engine.restTimer.total == 60)
    }

    @Test func skipWithoutARestChangesNothing() async throws {
        try startWorkout(on: engine)
        try await SkipRestIntent().perform()
        #expect(!engine.restTimer.isActive)
        #expect(engine.workout != nil)
    }

    /// With no rest left (an over rest a cold launch already forgot), +30 starts one from now, as on a warm over rest.
    @Test func addThirtyWithoutARestStartsOne() async throws {
        try startWorkout(on: engine)
        try await AddRestIntent(seconds: 30).perform()
        #expect(engine.restTimer.endsAt == clock.date.addingTimeInterval(30))
        #expect(engine.restTimer.total == 30)
    }

    @Test func addThirtyOnAnOverRestRestartsFromNow() async throws {
        try startWorkout(on: engine)
        try engine.startRest(seconds: 60)
        clock.date = clock.date.addingTimeInterval(61)
        try await AddRestIntent(seconds: 30).perform()
        #expect(engine.restTimer.endsAt == clock.date.addingTimeInterval(30))
    }

    // MARK: Done

    @Test func doneChecksTheSetAndStartsItsRest() async throws {
        let sets = try startWorkout(on: engine)
        let first = try #require(sets.first)
        #expect(!first.completed)

        try await DoneSetIntent(setID: first.id).perform()

        #expect(first.completed)
        #expect(first.completedAt == clock.date)
        #expect(engine.restTimer.isActive)
        #expect(engine.restTimer.setID == first.id)
    }

    @Test func doneOnAnEmptySetIsRefusedWithoutChange() async throws {
        let sets = try startWorkout(on: engine)
        let empty = sets[1]

        try await DoneSetIntent(setID: empty.id).perform()

        #expect(!empty.completed)
        #expect(!engine.restTimer.isActive)
    }

    @Test func doneOnAnUnknownSetChangesNothing() async throws {
        let sets = try startWorkout(on: engine)

        try await DoneSetIntent(setID: UUID()).perform()

        #expect(sets.allSatisfy { !$0.completed })
        #expect(!engine.restTimer.isActive)
    }

    @Test func doneWithAMalformedIDChangesNothing() async throws {
        let sets = try startWorkout(on: engine)
        var intent = DoneSetIntent()
        intent.setID = "not-a-uuid"

        try await intent.perform()
        var blank = DoneSetIntent()
        blank.setID = ""
        try await blank.perform()

        #expect(sets.allSatisfy { !$0.completed })
        #expect(!engine.restTimer.isActive)
    }

    @Test func doneOnAnAlreadyCheckedSetKeepsItsRest() async throws {
        let sets = try startWorkout(on: engine)
        let first = try #require(sets.first)
        try await DoneSetIntent(setID: first.id).perform()
        let completedAt = first.completedAt
        let end = engine.restTimer.endsAt

        clock.date = clock.date.addingTimeInterval(20)
        try await DoneSetIntent(setID: first.id).perform()

        #expect(first.completed)
        #expect(first.completedAt == completedAt)
        #expect(engine.restTimer.endsAt == end)
    }

    // MARK: Cold path

    /// A second engine on the same store writes the workout; the handler's engine was built before and holds none.
    private func coldHandlerEngine() throws -> (cold: ActiveWorkoutEngine, sets: [WorkoutSet]) {
        let cold = try makeEngine()
        #expect(cold.workout == nil)
        let sets = try startWorkout(on: engine)
        #expect(cold.workout == nil)
        ActivityIntentRouter.handler = EngineActivityIntentHandler(engine: cold)
        return (cold, sets)
    }

    @Test func skipResumesThePersistedWorkoutFirst() async throws {
        let (cold, _) = try coldHandlerEngine()
        try engine.startRest(seconds: 90)

        try await SkipRestIntent().perform()

        #expect(cold.workout?.id == engine.workout?.id)
        #expect(!cold.restTimer.isActive)
        #expect(cold.workout?.restEndsAt == nil)
    }

    @Test func addRestResumesThePersistedWorkoutFirst() async throws {
        let (cold, _) = try coldHandlerEngine()
        try engine.startRest(seconds: 90)

        try await AddRestIntent(seconds: 30).perform()

        #expect(cold.workout != nil)
        #expect(cold.restTimer.total == 120)
    }

    /// The cold launch: `resume()` already forgot the over rest the button was pressed on.
    @Test func addRestAfterAColdLaunchStartsARest() async throws {
        try startWorkout(on: engine)
        try engine.startRest(seconds: 60)
        clock.date = clock.date.addingTimeInterval(600)
        let cold = try makeEngine()
        #expect(!cold.restTimer.isActive)
        ActivityIntentRouter.handler = EngineActivityIntentHandler(engine: cold)

        try await AddRestIntent(seconds: 30).perform()

        #expect(cold.restTimer.endsAt == clock.date.addingTimeInterval(30))
        #expect(cold.restTimer.total == 30)
        #expect(try makeEngine().restTimer.endsAt == clock.date.addingTimeInterval(30))
    }

    @Test func doneResumesThePersistedWorkoutFirst() async throws {
        let (cold, sets) = try coldHandlerEngine()
        let first = try #require(sets.first)

        try await DoneSetIntent(setID: first.id).perform()

        #expect(cold.workout != nil)
        #expect(first.completed)
        #expect(cold.restTimer.setID == first.id)
    }

    // MARK: Flushing side effects

    /// A handler wired to fakes whose debounce is a minute: nothing the observers do on their own can land during a
    /// test, so whatever the fakes hold after `perform()` returns was flushed by the intent.
    private func flushingRig(for engine: ActiveWorkoutEngine) async -> (
        center: FakeNotificationCenter, provider: FakeLiveActivityProvider
    ) {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let clock = clock
        let notifier = RestNotifier(center: center, now: { clock.date }, debounce: .seconds(60))
        let provider = FakeLiveActivityProvider()
        let controller = LiveActivityController(provider: provider, debounce: .seconds(60))
        notifier.observe(engine)
        controller.observe(engine)
        await notifier.syncNow()
        await controller.reconcile()
        center.defersUntilFlush = true
        ActivityIntentRouter.handler = EngineActivityIntentHandler(
            engine: engine,
            activityController: controller,
            notifier: notifier
        )
        return (center, provider)
    }

    @Test func skipRemovesTheNotificationAndUpdatesTheActivityBeforeReturning() async throws {
        try startWorkout(on: engine)
        try engine.startRest(seconds: 90)
        let (center, provider) = await flushingRig(for: engine)
        let activity = try #require(provider.requested.first)
        #expect(center.pending[RestNotificationPlan.identifier] != nil)
        #expect(activity.contents.last?.state.restEndsAt != nil)

        try await SkipRestIntent().perform()

        #expect(center.pending.isEmpty)
        #expect(activity.contents.last?.state.restEndsAt == nil)
        #expect(center.log.contains("flush"))
    }

    @Test func doneSchedulesTheRestNotificationAndUpdatesTheActivityBeforeReturning() async throws {
        let sets = try startWorkout(on: engine)
        let (center, provider) = await flushingRig(for: engine)
        let activity = try #require(provider.requested.first)
        #expect(center.pending.isEmpty)

        try await DoneSetIntent(setID: try #require(sets.first).id).perform()

        let request = try #require(center.pending[RestNotificationPlan.identifier])
        #expect((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval == 60)
        #expect(activity.contents.last?.state.restEndsAt == clock.date.addingTimeInterval(60))
    }

    @Test func addRestMovesTheNotificationAndTheActivityBeforeReturning() async throws {
        try startWorkout(on: engine)
        try engine.startRest(seconds: 60)
        let (center, provider) = await flushingRig(for: engine)
        let activity = try #require(provider.requested.first)

        try await AddRestIntent(seconds: 30).perform()

        let request = try #require(center.pending[RestNotificationPlan.identifier])
        #expect((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval == 90)
        #expect(activity.contents.last?.state.restEndsAt == clock.date.addingTimeInterval(90))
    }

    @Test func aRefusedActionStillFlushesWhatChanged() async throws {
        let sets = try startWorkout(on: engine)
        let (center, _) = await flushingRig(for: engine)
        let flushes = center.log.filter { $0 == "flush" }.count

        _ = try await DoneSetIntent(setID: sets[1].id).perform()  // an empty set: refused

        #expect(center.log.filter { $0 == "flush" }.count == flushes + 1)
    }

    @Test func intentsWithNoWorkoutAtAllDoNothing() async throws {
        #expect(engine.workout == nil)

        try await SkipRestIntent().perform()
        try await AddRestIntent(seconds: 30).perform()
        try await DoneSetIntent(setID: UUID()).perform()

        #expect(engine.workout == nil)
    }

    @Test func intentsWithoutAHandlerDoNothing() async throws {
        let sets = try startWorkout(on: engine)
        try engine.startRest(seconds: 90)
        ActivityIntentRouter.handler = nil

        try await SkipRestIntent().perform()
        try await AddRestIntent(seconds: 30).perform()
        try await DoneSetIntent(setID: try #require(sets.first).id).perform()

        #expect(engine.restTimer.total == 90)
        #expect(sets.allSatisfy { !$0.completed })
    }
}
