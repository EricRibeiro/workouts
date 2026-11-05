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
    /// When true, `requestAuthorization()` waits for ``answerAuthorization()``, like the system alert waiting on a tap.
    var holdAuthorization = false
    /// When true, `schedule` is refused until status is authorized, as the real center does.
    var refusesUntilAuthorized = false
    private var answer: CheckedContinuation<Void, Never>?
    weak var delegate: (any UNUserNotificationCenterDelegate)?

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        if holdAuthorization { await withCheckedContinuation { answer = $0 } }
        status = grants ? .authorized : .denied
        return grants
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) { self.categories = categories }

    /// Taps the alert's button: the held `requestAuthorization()` returns.
    func answerAuthorization() {
        answer?.resume()
        answer = nil
    }

    func schedule(_ request: UNNotificationRequest) {
        // The real center refuses `add` while status is undetermined or denied.
        guard status == .authorized || !refusesUntilAuthorized else {
            log.append("refused")
            return
        }
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

    private func notifier(debounce: Duration = .zero) -> RestNotifier {
        let clock = clock
        return RestNotifier(center: center, now: { clock.date }, debounce: debounce)
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

    /// C-03: a rest started before the person answers the alert is refused by the center, so the grant must
    /// re-sync the plan; otherwise the first rest ever ends with no notification.
    @Test func firstWorkoutAsksForPermission() async throws {
        center.holdAuthorization = true
        center.refusesUntilAuthorized = true
        let engine = try engine()
        let notifier = notifier()
        notifier.observe(engine)
        try engine.startRest(seconds: 60)
        for _ in 0..<10 { await Task.yield() }
        #expect(center.authorizationRequests == 1)
        #expect(center.log.contains("refused"))
        #expect(center.pending.isEmpty)

        center.answerAuthorization()
        for _ in 0..<10 { await Task.yield() }
        let request = try #require(center.pending[RestNotificationPlan.identifier])
        #expect((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval == 60)
    }

    @Test func aDeniedGrantSchedulesNothing() async throws {
        center.grants = false
        center.refusesUntilAuthorized = true
        let engine = try engine()
        let notifier = notifier()
        notifier.observe(engine)
        try engine.startRest(seconds: 60)
        for _ in 0..<10 { await Task.yield() }
        #expect(center.pending.isEmpty)
    }

    // MARK: Coalescing

    private func scheduledSeconds() -> TimeInterval? {
        (center.pending[RestNotificationPlan.identifier]?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval
    }

    @Test func aBurstOfChangesSchedulesOnceWithTheFinalPlan() async throws {
        // Already allowed: the first-grant re-sync (C-03) is not part of what this test counts.
        center.status = .authorized
        let engine = try engine()
        let notifier = notifier(debounce: .milliseconds(80))
        notifier.observe(engine)
        center.log = []

        try engine.startRest(seconds: 60)
        for _ in 0..<5 { try engine.adjustRest(by: 30) }
        // Inside the window nothing has been touched yet.
        #expect(center.log.isEmpty)

        try await Task.sleep(for: .milliseconds(400))
        #expect(center.log.filter { $0 == "add" }.count == 1)
        #expect(center.log.filter { $0 == "removePending" }.count == 1)
        #expect(scheduledSeconds() == 210)

        // A change after the window is its own sync.
        try engine.adjustRest(by: 30)
        try await Task.sleep(for: .milliseconds(400))
        #expect(center.log.filter { $0 == "add" }.count == 2)
        #expect(scheduledSeconds() == 240)

        try engine.skipRest()
        try await Task.sleep(for: .milliseconds(400))
        #expect(center.pending.isEmpty)
    }
}
