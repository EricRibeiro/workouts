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
/// and ordered, which keeps "remove, then add" atomic from the notifier's point of view.
protocol NotificationCenterProviding: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func setCategories(_ categories: Set<UNNotificationCategory>)
    func schedule(_ request: UNNotificationRequest)
    func removePending(identifiers: [String])
    func removeDelivered(identifiers: [String])
    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?)
}

/// The real center.
final class SystemNotificationCenter: NotificationCenterProviding {
    private nonisolated static let logger = Logger(subsystem: "com.ericribeiro.Workouts", category: "RestNotifier")
    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }

    func schedule(_ request: UNNotificationRequest) {
        let identifier = request.identifier
        center.add(request) { error in
            if let error {
                Self.logger.error("Scheduling \(identifier) failed: \(error.localizedDescription)")
            } else {
                Self.logger.info("Scheduled \(identifier)")
            }
        }
    }

    func removePending(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDelivered(identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
        center.delegate = delegate
    }
}

/// Schedules the rest-end notification (`DECISIONS.md`, "Active workout behaviour"): a `.timeSensitive` local
/// notification at `restEndsAt` with the next set in the body and **Skip** / **+30 s** actions. In the foreground the
/// system banner is suppressed (``willPresent`` returns `[]`) and ``onRestEndedInForeground`` fires instead, for the
/// haptic and the flash (the UI sets it later).
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

    /// Called when a rest ends while the app is in the foreground (the system would have shown the notification).
    var onRestEndedInForeground: (() -> Void)?

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
        center.schedule(
            UNNotificationRequest(
                identifier: plan.identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
            )
        )
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

    /// Syncs the latest plan, whatever it is when this runs.
    private func syncNow(_ engine: ActiveWorkoutEngine) {
        sync(plan: engine.restNotificationPlan)
        if engine.workout != nil, !didRequestAuthorization {
            Task { await requestAuthorizationIfNeeded() }
        }
    }

    // MARK: - Responses

    /// The user tapped a notification button. A cold launch from the action may reach here before the engine resumed,
    /// so it resumes the persisted workout first. Unknown actions (including a plain tap) do nothing.
    func handleAction(_ actionIdentifier: String) {
        guard let action = RestNotificationAction(rawValue: actionIdentifier), let engine else { return }
        do {
            if engine.workout == nil { try engine.resume() }
            switch action {
            case .skip: try engine.skipRest()
            case .add30: try engine.adjustRest(by: RestNotificationAction.addSeconds)
            }
        } catch {
            logger.error("Rest action \(actionIdentifier) failed: \(error.localizedDescription)")
        }
    }

    /// What to show for a notification that arrives with the app in the foreground: nothing (the app plays a haptic and
    /// flashes), and the hook fires for the rest-end one.
    func presentationOptions(forNotification identifier: String) -> UNNotificationPresentationOptions {
        if identifier == RestNotificationPlan.identifier { onRestEndedInForeground?() }
        return []
    }
}

extension RestNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        return await MainActor.run { presentationOptions(forNotification: identifier) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        await MainActor.run { handleAction(action) }
    }
}
