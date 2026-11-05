//
//  LiveActivityController.swift
//  Workouts
//

import ActivityKit
import Foundation
import OSLog
import Observation
import WorkoutsKit

/// One running Live Activity, as far as the controller cares.
@MainActor
protocol LiveActivityHandle: AnyObject {
    /// Identity of the underlying activity (the same activity may be wrapped more than once).
    var id: String { get }
    var workoutID: UUID { get }
    func update(_ content: ActivityContent<WorkoutActivityState>) async
    func end(dismissalPolicy: ActivityUIDismissalPolicy) async
}

/// The slice of ActivityKit the controller uses, so tests can substitute a fake.
@MainActor
protocol LiveActivityProviding {
    /// Activities that already exist (from an earlier launch of the process).
    var existing: [any LiveActivityHandle] { get }
    /// Whether the person allows Live Activities (Settings, per app); requesting while off only throws.
    var areActivitiesEnabled: Bool { get }
    func request(
        workoutID: UUID,
        content: ActivityContent<WorkoutActivityState>
    ) throws -> any LiveActivityHandle
}

/// The real ActivityKit.
struct SystemLiveActivityProvider: LiveActivityProviding {
    var existing: [any LiveActivityHandle] {
        Activity<WorkoutActivityAttributes>.activities.map(SystemLiveActivity.init)
    }

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func request(
        workoutID: UUID,
        content: ActivityContent<WorkoutActivityState>
    ) throws -> any LiveActivityHandle {
        let activity = try Activity.request(
            attributes: WorkoutActivityAttributes(workoutID: workoutID),
            content: content,
            pushType: nil
        )
        return SystemLiveActivity(activity)
    }
}

final class SystemLiveActivity: LiveActivityHandle {
    private let activity: Activity<WorkoutActivityAttributes>

    init(_ activity: Activity<WorkoutActivityAttributes>) { self.activity = activity }

    var id: String { activity.id }
    var workoutID: UUID { activity.attributes.workoutID }

    func update(_ content: ActivityContent<WorkoutActivityState>) async {
        await activity.update(content)
    }

    func end(dismissalPolicy: ActivityUIDismissalPolicy) async {
        await activity.end(nil, dismissalPolicy: dismissalPolicy)
    }
}

/// Keeps one Live Activity in step with the engine (`DECISIONS.md`, "Native layer" → Live Activity): requested when a
/// workout appears, updated on every change to the activity state (check, skip, adjust, edit), ended with
/// `.immediate` dismissal when the workout is gone (Finish or Discard). `staleDate` is the rest's end and
/// `relevanceScore` is 1 while resting.
///
/// At launch it adopts a leftover activity of the same workout instead of requesting a duplicate, and ends any
/// activity that belongs to a different (or no) workout.
///
/// ### Keeping in step
/// ``observe(_:)`` mirrors `RestNotifier`: `withObservationTracking` over the activity state, and on every change a
/// hop to the next main-actor turn that re-arms the tracking and, after ``debounce`` (300 ms by default) of quiet,
/// re-reads and reconciles: a newer change cancels the pending reconcile, so a burst (a keystroke per change in a set
/// field) costs one `Activity.update` carrying the final state. The first reconcile at ``observe(_:)`` is immediate.
/// Reconciling is async (ActivityKit's `update` and `end`
/// are), so runs are serialised: a change that lands mid-run marks it dirty and the run loops once more.
@MainActor
final class LiveActivityController {
    private let provider: any LiveActivityProviding
    private let logger = Logger(subsystem: "com.ericribeiro.Workouts", category: "LiveActivity")
    private var engine: ActiveWorkoutEngine?
    private var current: (any LiveActivityHandle)?
    private var lastContent: ActivityContent<WorkoutActivityState>?
    private var isReconciling = false
    private var isDirty = false
    /// The workout whose unavailable Live Activity was already logged, so the log is one line per workout.
    private var loggedUnavailableFor: UUID?
    private let debounce: Duration
    private var pendingReconcile: Task<Void, Never>?

    /// `debounce` is how long the activity state must stay quiet before reconciling; tests pass `.zero` or a short value.
    init(provider: (any LiveActivityProviding)? = nil, debounce: Duration = .milliseconds(300)) {
        self.provider = provider ?? SystemLiveActivityProvider()
        self.debounce = debounce
    }

    /// The Live Activity content for `state`: stale when the rest ends, most relevant while resting.
    static func content(for state: WorkoutActivityState) -> ActivityContent<WorkoutActivityState> {
        ActivityContent(state: state, staleDate: state.restEndsAt, relevanceScore: state.isResting ? 1 : 0)
    }

    /// Reconciles now and again after every change to the engine's activity state. Call once per engine.
    func observe(_ engine: ActiveWorkoutEngine) {
        attach(engine)
        pendingReconcile?.cancel()
        pendingReconcile = nil
        track(engine)
        Task { await reconcile() }
    }

    /// Sets the engine without observing it; tests then call ``reconcile()`` themselves.
    func attach(_ engine: ActiveWorkoutEngine) {
        self.engine = engine
    }

    /// Arms one round of observation tracking; the change callback re-arms it and (re)schedules the debounced reconcile.
    private func track(_ engine: ActiveWorkoutEngine) {
        withObservationTracking {
            _ = engine.activityState
        } onChange: { [weak self] in
            Task { @MainActor in self?.changed(engine) }
        }
    }

    private func changed(_ engine: ActiveWorkoutEngine) {
        track(engine)
        pendingReconcile?.cancel()
        let debounce = debounce
        pendingReconcile = Task { @MainActor [weak self] in
            if debounce > .zero {
                do { try await Task.sleep(for: debounce) } catch { return }
            }
            guard !Task.isCancelled else { return }
            await self?.reconcile()
        }
    }

    /// Makes the system's activities match the engine: request, adopt, update or end. Safe to call often.
    func reconcile() async {
        if isReconciling {
            isDirty = true
            return
        }
        isReconciling = true
        defer { isReconciling = false }
        repeat {
            isDirty = false
            await apply()
        } while isDirty
    }

    private func apply() async {
        guard let engine else { return }
        guard let info = engine.activityStaticInfo, let state = engine.activityState else {
            await endAll(keeping: nil)
            return
        }
        let content = Self.content(for: state)

        if let activity = current, activity.workoutID == info.workoutID {
            guard !Self.isSame(content, lastContent) else { return }
            lastContent = content
            await activity.update(content)
            return
        }

        // A different workout than the one we hold, or nothing held yet (launch, first workout).
        await endAll(keeping: info.workoutID)
        if let adopted = current {
            lastContent = content
            await adopted.update(content)
            return
        }
        // Off in Settings: skip the request (it would only throw) and look again on the next change.
        guard provider.areActivitiesEnabled else {
            logUnavailable(for: info.workoutID, "Live Activities are turned off")
            return
        }
        do {
            current = try provider.request(workoutID: info.workoutID, content: content)
            lastContent = content
        } catch {
            // Too many activities, or a refusal: the app works without it; try again on the next change.
            logUnavailable(for: info.workoutID, "request failed: \(error.localizedDescription)")
        }
    }

    /// Logs why there is no Live Activity, once per workout rather than on every change.
    private func logUnavailable(for workoutID: UUID, _ reason: String) {
        guard loggedUnavailableFor != workoutID else { return }
        loggedUnavailableFor = workoutID
        logger.error("No Live Activity for this workout: \(reason)")
    }

    /// Ends every activity except one for `keep`, which becomes ``current`` (adopted) when it exists.
    private func endAll(keeping keep: UUID?) async {
        var adopted: (any LiveActivityHandle)?
        var all = provider.existing
        if let current, !all.contains(where: { $0.id == current.id }) { all.append(current) }
        for activity in all {
            if let keep, activity.workoutID == keep, adopted == nil {
                adopted = activity
            } else {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
        current = adopted
        lastContent = nil
    }

    private static func isSame(
        _ lhs: ActivityContent<WorkoutActivityState>,
        _ rhs: ActivityContent<WorkoutActivityState>?
    ) -> Bool {
        guard let rhs else { return false }
        return lhs.state == rhs.state && lhs.staleDate == rhs.staleDate && lhs.relevanceScore == rhs.relevanceScore
    }
}
