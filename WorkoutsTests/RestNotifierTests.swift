import Foundation
import SwiftData
import Testing
import UserNotifications
import WorkoutsKit

@testable import Workouts

@MainActor
final class FakeNotificationCenter: NotificationCenterProviding {
    var status: UNAuthorizationStatus = .notDetermined
    var grants = true
    var authorizationRequests = 0
    var categories: Set<UNNotificationCategory> = []
    var pending: [String: UNNotificationRequest] = [:]
    var delivered: Set<String> = []
    var log: [String] = []
    weak var delegate: (any UNUserNotificationCenterDelegate)?

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        status = grants ? .authorized : .denied
        return grants
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) { self.categories = categories }

    func schedule(_ request: UNNotificationRequest) {
        log.append("add")
        pending[request.identifier] = request
    }

    func removePending(identifiers: [String]) {
        log.append("removePending")
        identifiers.forEach { pending[$0] = nil }
    }

    func removeDelivered(identifiers: [String]) {
        log.append("removeDelivered")
        identifiers.forEach { delivered.remove($0) }
    }

    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) { self.delegate = delegate }
}

@MainActor
@Suite struct RestNotifierTests {
    final class Clock {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
    }

    let center = FakeNotificationCenter()
    let clock = Clock()
    /// Kept for the whole test: a context outlives neither its container nor the models fetched through it.
    let container: ModelContainer

    init() throws {
        container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
    }

    private func notifier() -> RestNotifier {
        let clock = clock
        return RestNotifier(center: center, now: { clock.date })
    }

    private func plan(in seconds: TimeInterval, body: String = "Rest over · Set 3 · 27.5 lb × 8")
        -> RestNotificationPlan
    {
        RestNotificationPlan(title: "Back Squat", body: body, fireDate: clock.date.addingTimeInterval(seconds))
    }

    private func engine() throws -> ActiveWorkoutEngine {
        let context = container.mainContext
        let store = ExerciseStore(catalog: try LibraryCatalog.bundled(in: .main))
        let settings = SettingsStore(backend: InMemoryBackend())
        let clock = clock
        let engine = try ActiveWorkoutEngine(context: context, store: store, settings: settings, now: { clock.date })
        try engine.startEmpty()
        return engine
    }

    // MARK: Categories

    @Test func activateRegistersSkipAndAdd30() throws {
        let notifier = notifier()
        notifier.activate()
        let category = try #require(center.categories.first)
        #expect(center.categories.count == 1)
        #expect(category.identifier == RestNotificationPlan.categoryIdentifier)
        #expect(category.actions.map(\.identifier) == ["skip", "add30"])
        #expect(category.actions.map(\.title) == ["Skip", "+30 s"])
        #expect(category.actions.allSatisfy { !$0.options.contains(.foreground) })
        #expect(center.delegate === notifier)
    }

    // MARK: Authorization

    @Test func authorizationIsRequestedOnceWhenUndetermined() async {
        let notifier = notifier()
        #expect(await notifier.requestAuthorizationIfNeeded())
        #expect(await notifier.requestAuthorizationIfNeeded())
        #expect(center.authorizationRequests == 1)
    }

    @Test func deniedIsNotAskedAgain() async {
        center.status = .denied
        let notifier = notifier()
        #expect(await notifier.requestAuthorizationIfNeeded() == false)
        #expect(center.authorizationRequests == 0)
    }

    @Test func nothingIsRequestedUntilAskedFor() {
        let notifier = notifier()
        notifier.activate()
        #expect(center.authorizationRequests == 0)
    }

    // MARK: sync

    @Test func syncSchedulesATimeSensitiveRequest() throws {
        let notifier = notifier()
        notifier.sync(plan: plan(in: 90))
        let request = try #require(center.pending[RestNotificationPlan.identifier])
        #expect(request.content.title == "Back Squat")
        #expect(request.content.body == "Rest over · Set 3 · 27.5 lb × 8")
        #expect(request.content.interruptionLevel == .timeSensitive)
        #expect(request.content.categoryIdentifier == RestNotificationPlan.categoryIdentifier)
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 90)
        #expect(!trigger.repeats)
    }

    @Test func syncReplacesAndClearsDeliveredFirst() throws {
        let notifier = notifier()
        notifier.sync(plan: plan(in: 90))
        center.delivered.insert(RestNotificationPlan.identifier)
        center.log = []
        notifier.sync(plan: plan(in: 120, body: "Rest over · Set 4"))
        #expect(center.pending.count == 1)
        let request = try #require(center.pending[RestNotificationPlan.identifier])
        #expect(request.content.body == "Rest over · Set 4")
        #expect((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval == 120)
        #expect(center.delivered.isEmpty)
        #expect(center.log.last == "add")
        #expect(center.log.firstIndex(of: "removePending")! < center.log.firstIndex(of: "add")!)
    }

    @Test func syncNilRemovesPendingAndDelivered() {
        let notifier = notifier()
        notifier.sync(plan: plan(in: 90))
        center.delivered.insert(RestNotificationPlan.identifier)
        notifier.sync(plan: nil)
        #expect(center.pending.isEmpty)
        #expect(center.delivered.isEmpty)
    }

    @Test func aPlanInThePastSchedulesNothingAndKeepsTheDeliveredBanner() {
        let notifier = notifier()
        notifier.sync(plan: plan(in: 90))
        center.delivered.insert(RestNotificationPlan.identifier)
        notifier.sync(plan: plan(in: 0))
        #expect(center.pending.isEmpty)
        #expect(center.delivered == [RestNotificationPlan.identifier])
    }

    // MARK: Foreground

    @Test func willPresentShowsNothingAndFiresTheHook() {
        let notifier = notifier()
        var fired = 0
        notifier.onRestEndedInForeground = { fired += 1 }
        #expect(notifier.presentationOptions(forNotification: RestNotificationPlan.identifier) == [])
        #expect(fired == 1)
        #expect(notifier.presentationOptions(forNotification: "other") == [])
        #expect(fired == 1)
    }

    // MARK: Responses

    @Test func actionsRouteToTheEngine() throws {
        let engine = try engine()
        let notifier = notifier()
        notifier.observe(engine)
        try engine.startRest(seconds: 60)
        let end = try #require(engine.restTimer.endsAt)

        notifier.handleAction("add30")
        #expect(engine.restTimer.endsAt == end.addingTimeInterval(30))

        notifier.handleAction(UNNotificationDefaultActionIdentifier)
        #expect(engine.restTimer.endsAt == end.addingTimeInterval(30))

        notifier.handleAction("skip")
        #expect(engine.restTimer.endsAt == nil)
    }

    @Test func actionResumesThePersistedWorkoutFirst() throws {
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        let store = ExerciseStore(catalog: try LibraryCatalog.bundled(in: .main))
        let settings = SettingsStore(backend: InMemoryBackend())
        let clock = clock
        func makeEngine() throws -> ActiveWorkoutEngine {
            try ActiveWorkoutEngine(
                context: container.mainContext,
                store: store,
                settings: settings,
                now: { clock.date }
            )
        }
        // Not live: created before the workout exists, as after a cold start from the action.
        let stale = try makeEngine()
        #expect(stale.workout == nil)
        let running = try makeEngine()
        try running.startEmpty()
        try running.startRest(seconds: 60)
        let end = try #require(running.restTimer.endsAt)

        let notifier = notifier()
        notifier.observe(stale)
        notifier.handleAction("add30")
        #expect(stale.workout != nil)
        #expect(stale.restTimer.endsAt == end.addingTimeInterval(30))
    }

    // MARK: Observation

    @Test func observingKeepsTheScheduleInStepWithTheEngine() async throws {
        let engine = try engine()
        let notifier = notifier()
        notifier.observe(engine)
        #expect(center.pending.isEmpty)

        try engine.startRest(seconds: 60)
        await Task.yield()
        let request = try #require(center.pending[RestNotificationPlan.identifier])
        #expect((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval == 60)

        try engine.adjustRest(by: 30)
        await Task.yield()
        let moved = try #require(center.pending[RestNotificationPlan.identifier])
        #expect((moved.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval == 90)

        try engine.skipRest()
        await Task.yield()
        #expect(center.pending.isEmpty)
    }

    @Test func firstWorkoutAsksForPermission() async throws {
        let engine = try engine()
        let notifier = notifier()
        notifier.observe(engine)
        for _ in 0..<5 { await Task.yield() }
        #expect(center.authorizationRequests == 1)
    }
}
