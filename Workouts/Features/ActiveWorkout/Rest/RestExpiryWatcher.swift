//
//  RestExpiryWatcher.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// Watches the running rest for as long as the active-workout cover is up: at zero it plays the success haptic and posts a VoiceOver "Rest over" announcement, and
/// ``RestTimer/expiredGraceSeconds`` later it forgets the rest (``ActiveWorkoutEngine/tickRest()``).
///
/// It lives on the cover's `NavigationStack`, not on the rest ring, because the ring leaves the toolbar while a set field
/// has focus (the normal flow: check a set, then type the next one while resting) and a task there would be cancelled.
/// This is the only watcher while the cover is up; ``ResumeControl`` owns the same job while the cover is closed.
private struct RestExpiryWatcher: ViewModifier {
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    /// Bumped once when a rest reaches 0 while this modifier watches; drives the success haptic.
    @State private var restEndCount = 0

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.success, trigger: restEndCount)
            .task(id: engine?.restTimer.endsAt) {
                guard let engine, let endsAt = engine.restTimer.endsAt else { return }
                await engine.awaitRestExpiry(endsAt: endsAt) {
                    restEndCount += 1
                    // The banner is suppressed in the foreground, so VoiceOver would otherwise get nothing.
                    AccessibilityNotification.Announcement(RestAccessibility.overAnnouncement).post()
                }
            }
    }
}

extension View {
    /// Plays the rest-end haptic and forgets the over rest while this view is up, wherever the rest ring is.
    func restExpiryWatcher() -> some View {
        modifier(RestExpiryWatcher())
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
