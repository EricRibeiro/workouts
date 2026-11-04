//
//  ResumeControl.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The minimised workout's resume control (task 2.7, DECISIONS "Minimised workout"): while a workout runs and its cover is
/// not showing, one toolbar item restores the cover. Toolbar items do not inherit on push, so every screen's root applies
/// this modifier.
///
/// A `Label` with an `Image` icon, because that is what the closed Duo moves into the trailing strip. The icon is the
/// draining rest arc while a rest runs and a workout symbol otherwise; the elapsed time or the countdown rides in the
/// accessibility label (the strip drops values).
private struct ResumeControl: ViewModifier {
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    @State private var restoreCount = 0

    func body(content: Content) -> some View {
        content
            .toolbar {
                if let engine, let navigation, let workout = engine.workout, !navigation.isWorkoutCoverPresented {
                    // Its own glass group, still last: the ring is a status, not a third action beside the others.
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                    ToolbarItem(placement: .primaryAction) {
                        ResumeRingButton(engine: engine, startedAt: workout.startedAt) {
                            restoreCount += 1
                            navigation.presentWorkout()
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: restoreCount)
    }
}

extension View {
    /// Adds the resume ring to this screen's toolbar while a minimised (or not yet opened) workout runs.
    func resumeControl() -> some View {
        modifier(ResumeControl())
    }
}

private struct ResumeRingButton: View {
    let engine: ActiveWorkoutEngine
    let startedAt: Date
    let restore: () -> Void
    /// Updated by a 1 s loop; the arc and the accessibility text derive from it.
    @State private var now = Date.now
    /// Bumped by the 1 s loop when the rest reaches 0 while the cover is closed; drives the success haptic.
    @State private var restEndCount = 0
    @ScaledMetric(relativeTo: .body) private var arcSize: CGFloat = 22

    var body: some View {
        let timer = engine.restTimer
        let state = Self.state(startedAt: startedAt, endsAt: timer.endsAt, now: now)
        Button(action: restore) {
            Label {
                Text("Resume workout")
            } icon: {
                if let endsAt = timer.endsAt, let total = timer.total {
                    let remaining = max(0, endsAt.timeIntervalSince(now))
                    RestArc.image(
                        fraction: min(1, remaining / Double(max(1, total))),
                        size: arcSize,
                        label: Text("Resume workout"),
                        tint: remaining <= 0 ? .ok : nil
                    )
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                }
            }
        }
        .accessibilityLabel("Resume workout, \(state)")
        .accessibilityIdentifier("resume.ring")
        // The engine keeps an over rest for a few seconds (the flash); with the cover closed nothing else forgets it.
        .sensoryFeedback(.success, trigger: restEndCount)
        .task(id: timer.endsAt) {
            now = .now
            // A rest already over when this view appears must not buzz.
            var hasEnded = timer.endsAt.map { $0 <= now } ?? true
            while !Task.isCancelled {
                // Cancellation ends the loop through `Task.isCancelled`; there is nothing to report.
                try? await Task.sleep(for: .seconds(1))
                now = .now
                if !hasEnded, let endsAt = engine.restTimer.endsAt, endsAt <= now {
                    hasEnded = true
                    restEndCount += 1
                }
                // A failed save while forgetting an over rest is harmless: the next tick retries it, so no alert
                // (it would repeat every second).
                if engine.restTimer.endsAt != nil, (try? engine.tickRest()) == true { break }
            }
        }
    }

    /// "rest 4:57" while a rest runs, "12:34 elapsed" otherwise.
    private static func state(startedAt: Date, endsAt: Date?, now: Date) -> String {
        if let endsAt {
            let remaining = Int(max(0, endsAt.timeIntervalSince(now)).rounded(.up))
            return "rest \(ElapsedFormat.string(seconds: remaining))"
        }
        return "\(ElapsedFormat.string(seconds: Int(now.timeIntervalSince(startedAt)))) elapsed"
    }
}
