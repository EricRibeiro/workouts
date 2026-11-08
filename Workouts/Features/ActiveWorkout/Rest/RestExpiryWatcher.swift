//
//  RestExpiryWatcher.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// Watches the running rest while `isActive`: at zero it plays the success haptic and posts a VoiceOver "Rest over"
/// announcement, and ``RestTimer/expiredGraceSeconds`` later it forgets the rest (``ActiveWorkoutEngine/tickRest()``).
///
/// There are exactly two hosts, never active together, so the haptic never doubles. The cover's `NavigationStack` hosts
/// one for as long as the cover is up (not on the rest ring, because the ring leaves the toolbar while a set field has
/// focus, the normal flow: check a set, then type the next one while resting, and a task there would be cancelled).
/// `RootView` hosts the other around the `TabView` with `isActive` false while the cover is on screen, so a minimised
/// workout's rest also ends audibly on a pushed screen (a past workout, an exercise's detail) where no resume ring exists.
private struct RestExpiryWatcher: ViewModifier {
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    var isActive: Bool
    /// Bumped once when a rest reaches 0 while this modifier watches; drives the success haptic.
    @State private var restEndCount = 0

    /// The task restarts when the rest changes or the watcher is switched on or off.
    private struct WatchKey: Equatable {
        var endsAt: Date?
        var isActive: Bool
    }

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.success, trigger: restEndCount)
            .task(id: WatchKey(endsAt: engine?.restTimer.endsAt, isActive: isActive)) {
                guard isActive, let engine, let endsAt = engine.restTimer.endsAt else { return }
                await engine.awaitRestExpiry(endsAt: endsAt) {
                    restEndCount += 1
                    // The banner is suppressed in the foreground, so VoiceOver would otherwise get nothing.
                    AccessibilityNotification.Announcement(RestAccessibility.overAnnouncement).post()
                }
            }
    }
}

extension View {
    /// Plays the rest-end haptic and forgets the over rest while this view is up and `isActive`, wherever the rest ring is.
    func restExpiryWatcher(isActive: Bool = true) -> some View {
        modifier(RestExpiryWatcher(isActive: isActive))
    }
}

extension ActiveWorkoutEngine {
    /// Sleeps until the rest ending at `endsAt` is over, runs `onEnded` once (the success haptic), then sleeps through
    /// ``RestTimer/expiredGraceSeconds`` and forgets the rest with ``tickRest()``. Two sleeps on the persisted end date,
    /// not a per-second poll. A rest that is already over when this starts does not call `onEnded` (relaunch must not
    /// buzz), nor does one this wakes for more than ``RestTimer/buzzToleranceSeconds`` late. Returns early when cancelled (the rest changed or the view went away).
    func awaitRestExpiry(endsAt: Date, onEnded: () -> Void) async {
        if endsAt > .now {
            guard await Self.sleep(until: endsAt) else { return }
            // A wake-up long after the end (suspended in the background) clears silently instead of buzzing.
            if RestTimer.shouldBuzz(endsAt: endsAt, wokeAt: .now) { onEnded() }
        }
        let forgetAt = endsAt.addingTimeInterval(TimeInterval(RestTimer.expiredGraceSeconds))
        while true {
            guard await Self.sleep(until: forgetAt) else { return }
            // A failed save while forgetting an over rest is harmless: retry once a second (no alert, it would repeat).
            if (try? tickRest()) == true { return }
            guard await Self.sleep(until: max(forgetAt, .now.addingTimeInterval(1))) else { return }
        }
    }

    /// `Task.sleep` until a wall-clock date, re-checking the date after waking. False when cancelled.
    private static func sleep(until date: Date) async -> Bool {
        let clock = ContinuousClock()
        while date.timeIntervalSinceNow > 0 {
            do {
                try await Task.sleep(until: clock.now.advanced(by: .seconds(date.timeIntervalSinceNow)), clock: clock)
            } catch {
                return false
            }
        }
        return !Task.isCancelled
    }
}
