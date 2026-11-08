//
//  RestNotifier.swift
//  Workouts
//

import Foundation
import OSLog
import Observation
import UserNotifications
import WorkoutsKit

/// The slice of `UNUserNotificationCenter` the notifier uses, so tests can substitute a fake. Calls are fire-and-forget
/// and ordered, which keeps "remove, then add" atomic from the notifier's point of view; ``flush()`` is the one way to
/// wait for them.
protocol NotificationCenterProviding: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func setCategories(_ categories: Set<UNNotificationCategory>)
    /// Schedules a one-shot notification at `fireDate`. The trigger interval is computed when the call is carried out
    /// (``SystemNotificationCenter/request(identifier:content:fireDate:now:)``), not when it is made, so time spent
    /// waiting in the center's queue does not push the alarm late.
    func schedule(identifier: String, content: UNNotificationContent, fireDate: Date)
    func removePending(identifiers: [String])
    func removeDelivered(identifiers: [String])
    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?)
    /// Returns once every call made so far has been carried out by the system (adds acknowledged, removals done). A
    /// background action awaits it before returning, since the system may suspend the app right after.
    func flush() async
}

/// The real center.
final class SystemNotificationCenter: NotificationCenterProviding {
    private nonisolated static let logger = Logger(subsystem: "com.ericribeiro.Workouts", category: "RestNotifier")
    private var center: UNUserNotificationCenter { .current() }
    /// The center's remove/add/category calls are synchronous XPC round trips to the notification daemon. On the main
    /// thread at launch (``RestNotifier/observe(_:)`` runs from `WorkoutsApp.init`) a slow daemon held the app past the
    /// launch watchdog (0x8BADF00D). They run here instead: off the main thread, one at a time and in call order, so
    /// "remove, then add" keeps its order.
    private nonisolated static let queue = DispatchQueue(label: "com.ericribeiro.Workouts.notifications")
    /// Every call enters before it is queued and leaves when the system has answered; ``flush()`` waits for it to empty.
    private nonisolated static let pendingCalls = DispatchGroup()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) {
        Self.pendingCalls.enter()
        Self.queue.async {
            UNUserNotificationCenter.current().setNotificationCategories(categories)
            Self.pendingCalls.leave()
        }
    }

    /// The request for `fireDate` as of `now`: the interval is measured from the moment of this call, at least one
    /// second (a zero or negative interval is refused by the system).
    nonisolated static func request(
        identifier: String,
        content: UNNotificationContent,
        fireDate: Date,
        now: Date
    ) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, fireDate.timeIntervalSince(now)),
                repeats: false
            )
        )
    }

    func schedule(identifier: String, content: UNNotificationContent, fireDate: Date) {
        Self.pendingCalls.enter()
        Self.queue.async {
            // Computed here, inside the queue block, so a backed-up queue does not shift the fire date.
            let request = Self.request(identifier: identifier, content: content, fireDate: fireDate, now: .now)
            UNUserNotificationCenter.current().add(request) { error in
                defer { Self.pendingCalls.leave() }
                if let error {
                    Self.logger.error("Scheduling \(identifier) failed: \(error.localizedDescription)")
                } else {
                    Self.logger.info("Scheduled \(identifier)")
                }
            }
        }
    }

    func removePending(identifiers: [String]) {
        Self.pendingCalls.enter()
        Self.queue.async {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
            Self.pendingCalls.leave()
        }
    }

    func removeDelivered(identifiers: [String]) {
        Self.pendingCalls.enter()
        Self.queue.async {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
            Self.pendingCalls.leave()
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            Self.pendingCalls.notify(queue: Self.queue) { @Sendable in continuation.resume() }
        }
    }

    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
        center.delegate = delegate
    }
}

/// Schedules the rest-end notification (`DECISIONS.md`, "Active workout behaviour"): a `.timeSensitive` local
/// notification at `restEndsAt` with the next set in the body and **Skip** / **+30 s** actions. In the foreground the
/// system banner is suppressed (``willPresent`` returns `[]`); the cover's ``RestExpiryWatcher`` and the resume control
/// play the haptic themselves when the countdown reaches zero (`restEndCount`).
///
/// It is also the `UNUserNotificationCenterDelegate`, so the owner must keep it alive (the center holds it weakly).
///
/// ### Keeping the schedule in step
/// ``observe(_:)`` runs `withObservationTracking` over `engine.restNotificationPlan` and re-syncs on every change, so no
/// call site that mutates the engine (check, uncheck, rest buttons, finish, discard, editing the next set's values) has
/// to remember to do it. The change callback fires before the mutation lands, so it hops to the next main-actor turn,
/// re-arms the tracking, and schedules a re-read after ``debounce`` (300 ms by default); a newer change cancels the
/// pending re-read, so a burst (a keystroke per change in a set field) removes and re-adds the notification once, with
/// the final plan. The first sync at ``observe(_:)`` is immediate.
@MainActor
final class RestNotifier: NSObject {
    private let center: any NotificationCenterProviding
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.ericribeiro.Workouts", category: "RestNotifier")
    private var engine: ActiveWorkoutEngine?
    private var didRequestAuthorization = false
    private let debounce: Duration
    private var pendingSync: Task<Void, Never>?
    /// Awaited after a notification button's effect, to bring the rest of the app's system state (the Live Activity)
    /// up to date before the response handler returns. The app sets it; tests may leave it nil.
    /// Called for a tap on the notification body (not a button): the app shows the running workout.
    var openWorkout: (@MainActor () -> Void)?
    var flushLiveActivity: (@MainActor () async -> Void)?

    /// `debounce` is how long the engine must stay quiet before the schedule is re-synced; tests pass `.zero` or a short
    /// value.
    init(
        center: any NotificationCenterProviding = SystemNotificationCenter(),
        now: @escaping () -> Date = Date.init,
        debounce: Duration = .milliseconds(300)
    ) {
        self.center = center
        self.now = now
        self.debounce = debounce
        super.init()
    }

    /// Registers the action category and becomes the center's delegate. Call once at launch, before the app finishes
    /// launching if possible, so a cold-start action is delivered.
    func activate() {
        center.setCategories([Self.category])
        center.setDelegate(self)
    }

    static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: RestNotificationPlan.categoryIdentifier,
            actions: RestNotificationAction.allCases.map {
                // Not `.foreground`: both run in the background without opening the app.
                UNNotificationAction(identifier: $0.rawValue, title: $0.title, options: [])
            },
            intentIdentifiers: [],
            options: []
        )
    }

    // MARK: - Authorization

    /// Asks for permission the first time it is called while status is undetermined (the first workout), never at
    /// launch. Returns whether notifications are allowed afterwards.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        switch await center.authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            guard !didRequestAuthorization else { return false }
            didRequestAuthorization = true
            do {
                return try await center.requestAuthorization()
            } catch {
                logger.error("Notification authorization failed: \(error.localizedDescription)")
                return false
            }
        @unknown default:
            return false
        }
    }

    // MARK: - Scheduling

    /// Makes the center's request for the rest-end identifier match `plan`: nil removes it, pending and delivered; a
    /// future plan replaces it (delivered too, so a stale "Rest over" does not outlive a new rest); a plan already past
    /// schedules nothing (the rest ended; nothing is left to announce, and a request in the past would be refused).
    func sync(plan: RestNotificationPlan?) {
        let ids = [RestNotificationPlan.identifier]
        let remainingText = plan.map { String($0.fireDate.timeIntervalSince(now())) } ?? "none"
        logger.info("sync plan=\(plan == nil ? "nil" : "present") remaining=\(remainingText)")
        guard let plan else {
            center.removePending(identifiers: ids)
            center.removeDelivered(identifiers: ids)
            return
        }
        center.removePending(identifiers: ids)
        let remaining = plan.fireDate.timeIntervalSince(now())
        guard remaining > 0 else { return }
        center.removeDelivered(identifiers: ids)

        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = plan.categoryIdentifier
        center.schedule(identifier: plan.identifier, content: content, fireDate: plan.fireDate)
    }

    /// Syncs now and again (debounced) after every change to the engine's rest plan. Also asks for permission once a
    /// workout exists. Call once per engine.
    func observe(_ engine: ActiveWorkoutEngine) {
        self.engine = engine
        pendingSync?.cancel()
        pendingSync = nil
        track(engine)
        syncNow(engine)
    }

    /// Arms one round of observation tracking; the change callback re-arms it and (re)schedules the debounced sync.
    private func track(_ engine: ActiveWorkoutEngine) {
        withObservationTracking {
            _ = engine.restNotificationPlan
            _ = engine.workout != nil
        } onChange: { [weak self] in
            Task { @MainActor in self?.changed(engine) }
        }
    }

    private func changed(_ engine: ActiveWorkoutEngine) {
        track(engine)
        pendingSync?.cancel()
        pendingSync = nil
        guard debounce > .zero else { return syncNow(engine) }
        let debounce = debounce
        pendingSync = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: debounce) } catch { return }
            guard !Task.isCancelled else { return }
            self?.syncNow(engine)
        }
    }

    /// Brings the center in step with the engine's rest plan right now, bypassing the debounce, and returns once the
    /// system has carried the calls out. Background actions (the intents, a notification button) await it: the system
    /// may suspend the app as soon as they return, which would leave a skipped rest's notification armed or a new
    /// rest's unscheduled. Does not ask for permission (nothing can answer a prompt in the background).
    func syncNow() async {
        pendingSync?.cancel()
        pendingSync = nil
        if let engine { sync(plan: engine.restNotificationPlan) }
        await center.flush()
    }

    /// Syncs the latest plan, whatever it is when this runs.
    private func syncNow(_ engine: ActiveWorkoutEngine) {
        sync(plan: engine.restNotificationPlan)
        if engine.workout != nil, !didRequestAuthorization {
            // The center refuses a request while status is undetermined, so a rest started before the answer would
            // be lost: once the grant lands, schedule whatever the plan is by then.
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Only a prompt that was actually shown needs the re-sync; already-allowed needs none.
                let wasUndetermined = await center.authorizationStatus() == .notDetermined
                guard await requestAuthorizationIfNeeded(), wasUndetermined else { return }
                sync(plan: engine.restNotificationPlan)
            }
        }
    }

    // MARK: - Responses

    /// The user tapped a notification button. A cold launch from the action may reach here before the engine resumed,
    /// so it resumes the persisted workout first. A plain tap on the body opens the workout; other unknown actions do
    /// nothing.
    func handleAction(_ actionIdentifier: String) {
        if actionIdentifier == UNNotificationDefaultActionIdentifier {
            openWorkout?()
            return
        }
        guard let action = RestNotificationAction(rawValue: actionIdentifier), let engine else { return }
        do {
            if engine.workout == nil { try engine.resume() }
            switch action {
            case .skip: try engine.skipRest()
            // Restarts when the rest is over or already forgotten (a cold launch restores to idle first), as the
            // warm path does for an over rest.
            case .add30: try engine.extendOrRestartRest(by: RestNotificationAction.addSeconds)
            }
        } catch {
            logger.error("Rest action \(actionIdentifier) failed: \(error.localizedDescription)")
        }
    }

    /// ``handleAction(_:)``, then everything the action changed pushed to the system (this notification schedule and
    /// the Live Activity) before returning, so the response handler's return does not outrun the side effects.
    func respond(to actionIdentifier: String) async {
        handleAction(actionIdentifier)
        await syncNow()
        await flushLiveActivity?()
    }

}

extension RestNotifier: UNUserNotificationCenterDelegate {
    /// UIKit calls its delegate on an arbitrary thread and, for a response that opens the app, requires the completion
    /// handler back on the main thread. The `async` variants return it from whatever executor the method resumes on
    /// (the global one, since these are `nonisolated`), which traps; so these are the handler variants, and the handler
    /// is called on the main actor.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        // Nothing in the foreground: the cover's RestExpiryWatcher (or the resume control) plays the haptic itself.
        Task { @MainActor in completionHandler([]) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        handleResponse(actionIdentifier: response.actionIdentifier, completionHandler: completionHandler)
    }

    /// The body of ``userNotificationCenter(_:didReceive:withCompletionHandler:)``, split out so a test can drive it
    /// without a `UNNotificationResponse` (which cannot be constructed). Runs ``respond(to:)`` on the main actor, then
    /// calls `completionHandler` there.
    nonisolated func handleResponse(actionIdentifier: String, completionHandler: @escaping @Sendable () -> Void) {
        Task { @MainActor in
            await respond(to: actionIdentifier)
            completionHandler()
        }
    }
}
