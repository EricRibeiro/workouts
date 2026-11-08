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
    /// `.ended` once the system ended it (Live Activities turned off, the time limit), `.dismissed` once the person
    /// swiped it away; only `.active` and `.stale` activities can still be updated.
    var activityState: ActivityState { get }
    func update(_ content: ActivityContent<WorkoutActivityState>) async
    func end(dismissalPolicy: ActivityUIDismissalPolicy) async
}

/// The slice of ActivityKit the controller uses, so tests can substitute a fake. The calls are `async` because the real
/// ones are synchronous XPC round trips to `chronod` that must not run on the main thread.
@MainActor
protocol LiveActivityProviding {
    /// Activities that already exist (from an earlier launch of the process).
    func existingActivities() async -> [any LiveActivityHandle]
    /// Whether the person allows Live Activities (Settings, per app); requesting while off only throws.
    func activitiesEnabled() async -> Bool
    func request(
        workoutID: UUID,
        content: ActivityContent<WorkoutActivityState>
    ) async throws -> any LiveActivityHandle
}

/// The real ActivityKit.
///
/// `Activity.activities`, `ActivityAuthorizationInfo` and `Activity.request` are synchronous XPC round trips to
/// `chronod`. The controller's first reconcile runs from `WorkoutsApp.init`, so on the main thread a slow daemon could
/// hold the app past the launch watchdog (the same class of stall as `SystemNotificationCenter`, JC80). They run on
/// ``queue`` instead, one at a time and in call order, and the caller awaits the result, so reconcile still finishes
/// before the next start or update. The handles are wrapped back on the main actor.
struct SystemLiveActivityProvider: LiveActivityProviding {
    private nonisolated static let queue = DispatchQueue(label: "com.ericribeiro.Workouts.liveactivity")

    func existingActivities() async -> [any LiveActivityHandle] {
        let activities = await withCheckedContinuation { continuation in
            Self.queue.async {
                continuation.resume(returning: Activity<WorkoutActivityAttributes>.activities)
            }
        }
        return activities.map(SystemLiveActivity.init)
    }

    func activitiesEnabled() async -> Bool {
        await withCheckedContinuation { continuation in
            Self.queue.async {
                continuation.resume(returning: ActivityAuthorizationInfo().areActivitiesEnabled)
            }
        }
    }

    func request(
        workoutID: UUID,
        content: ActivityContent<WorkoutActivityState>
    ) async throws -> any LiveActivityHandle {
        let activity = try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                continuation.resume(
                    with: Result {
                        try Activity.request(
                            attributes: WorkoutActivityAttributes(workoutID: workoutID),
                            content: content,
                            pushType: nil
                        )
                    }
                )
            }
        }
        return SystemLiveActivity(activity)
    }
}

final class SystemLiveActivity: LiveActivityHandle {
    private let activity: Activity<WorkoutActivityAttributes>

    init(_ activity: Activity<WorkoutActivityAttributes>) { self.activity = activity }

    var id: String { activity.id }
    var workoutID: UUID { activity.attributes.workoutID }
    var activityState: ActivityState { activity.activityState }

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
/// At launch it adopts a leftover activity of the same workout (only one that is still `.active` or `.stale`)
/// instead of requesting a duplicate, and ends any activity that belongs to a different (or no) workout.
///
/// The system can end an activity on its own (Live Activities turned off in Settings, the 8-hour limit): the held
/// activity is then dropped and the next pass requests a new one. When the person swipes it away it is `.dismissed`
/// instead, and that workout does not get another one.
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
    /// The run in flight, nil when idle; it clears itself with no suspension between its last pass and the clear.
    private var reconcileRun: Task<Void, Never>?
    private var isDirty = false
    /// The workout whose unavailable Live Activity was already logged, so the log is one line per workout.
    private var loggedUnavailableFor: UUID?
    /// Workouts whose activity the person dismissed; no new one is requested for them. Cleared when no workout is left.
    private var dismissedWorkouts: Set<UUID> = []
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

    /// Makes the system's activities match the engine: request, adopt, update or end. Safe to call often. Runs are
    /// serialised: a call that lands mid-run marks it dirty and, like every call, returns only when the run (including
    /// that extra pass) has finished, so the caller may rely on the system having the engine's state.
    func reconcile() async {
        if let reconcileRun {
            isDirty = true
            await reconcileRun.value
            return
        }
        let run = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                isDirty = false
                await apply()
            } while isDirty
            reconcileRun = nil
        }
        reconcileRun = run
        await run.value
    }

    /// Reconciles right now, bypassing the debounce, and returns once ActivityKit has taken the update. A background
    /// action (a Live Activity button, a notification button) awaits this before it returns, because the system may
    /// suspend the app the moment it does. Foreground changes keep the debounce.
    func syncNow() async {
        pendingReconcile?.cancel()
        pendingReconcile = nil
        await reconcile()
    }

    private func apply() async {
        guard let engine else { return }
        guard let info = engine.activityStaticInfo, let state = engine.activityState else {
            dismissedWorkouts.removeAll()
            await endAll(keeping: nil)
            return
        }
        let content = Self.content(for: state)

        if let activity = current, activity.workoutID == info.workoutID {
            switch activity.activityState {
            case .active, .stale:
                break
            case .dismissed:
                // The person swiped it away: remember, and do not bring it back.
                dismissedWorkouts.insert(info.workoutID)
                current = nil
                lastContent = nil
                return
            default:
                // Ended by the system: updates would go nowhere. Drop it; the request below makes a new one.
                current = nil
                lastContent = nil
            }
        }

        if let activity = current, activity.workoutID == info.workoutID {
            guard !Self.isSame(content, lastContent) else { return }
            lastContent = content
            await activity.update(content)
            return
        }

        // A different workout than the one we hold, or nothing held yet (launch, first workout).
        await endAll(keeping: info.workoutID)
        if dismissedWorkouts.contains(info.workoutID) { return }
        if let adopted = current {
            lastContent = content
            await adopted.update(content)
            return
        }
        // Off in Settings: skip the request (it would only throw) and look again on the next change.
        guard await provider.activitiesEnabled() else {
            logUnavailable(for: info.workoutID, "Live Activities are turned off")
            return
        }
        do {
            current = try await provider.request(workoutID: info.workoutID, content: content)
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
        var all = await provider.existingActivities()
        if let current, !all.contains(where: { $0.id == current.id }) { all.append(current) }
        for activity in all {
            if let keep, activity.workoutID == keep, adopted == nil, Self.isLive(activity.activityState) {
                adopted = activity
            } else {
                if let keep, activity.workoutID == keep, activity.activityState == .dismissed {
                    dismissedWorkouts.insert(keep)
                }
                await activity.end(dismissalPolicy: .immediate)
            }
        }
        current = adopted
        lastContent = nil
    }

    private static func isLive(_ state: ActivityState) -> Bool {
        state == .active || state == .stale
    }

    private static func isSame(
        _ lhs: ActivityContent<WorkoutActivityState>,
        _ rhs: ActivityContent<WorkoutActivityState>?
    ) -> Bool {
        guard let rhs else { return false }
        return lhs.state == rhs.state && lhs.staleDate == rhs.staleDate && lhs.relevanceScore == rhs.relevanceScore
    }
}
