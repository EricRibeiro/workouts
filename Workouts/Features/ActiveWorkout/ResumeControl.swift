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
/// A `Label` with an `Image` icon, because that is what the closed Duo moves into the trailing strip. The icon is one ring
/// in every state, Fitness-style, with a `dumbbell.fill` glyph inside (not the Exercises tab's figure, which sits in the same
/// strip, and not the `stopwatch`, which means "start a rest"): a bare accent track while no rest runs, the accent arc
/// draining while one does, and an ok-coloured ring with a `checkmark` while the finished rest sits in its grace. The elapsed
/// time or the countdown rides in the accessibility label (the strip drops values).
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
    /// Bumped once when the rest reaches 0 while the cover is closed; drives the success haptic.
    @State private var restEndCount = 0
    @ScaledMetric(relativeTo: .body) private var arcSize: CGFloat = 24

    var body: some View {
        let timer = engine.restTimer
        Group {
            // Only a rest needs the per-second redraw; the idle ring is static and its elapsed time rides in the
            // accessibility label, read when VoiceOver asks.
            if timer.endsAt != nil, timer.total != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    button(now: context.date, timer: timer)
                }
            } else {
                button(now: .now, timer: timer)
            }
        }
        // The engine keeps an over rest for a few seconds (the flash); with the cover closed nothing else forgets it.
        .sensoryFeedback(.success, trigger: restEndCount)
        .task(id: timer.endsAt) {
            guard let endsAt = timer.endsAt else { return }
            await engine.awaitRestExpiry(endsAt: endsAt) { restEndCount += 1 }
        }
    }

    private func button(now: Date, timer: RestTimer) -> some View {
        let state = Self.state(startedAt: startedAt, endsAt: timer.endsAt, now: now)
        return Button(action: restore) {
            Label {
                Text("Resume workout")
            } icon: {
                if let endsAt = timer.endsAt, let total = timer.total {
                    let remaining = max(0, endsAt.timeIntervalSince(now))
                    let isOver = remaining <= 0
                    RestArc.image(
                        fraction: min(1, remaining / Double(max(1, total))),
                        size: arcSize,
                        label: Text("Resume workout"),
                        tint: isOver ? .ok : .accentColor,
                        glyph: isOver ? "checkmark" : "dumbbell.fill"
                    )
                } else {
                    RestArc.image(
                        fraction: 0,
                        size: arcSize,
                        label: Text("Resume workout"),
                        tint: .accentColor,
                        glyph: "dumbbell.fill"
                    )
                }
            }
        }
        .accessibilityLabel("Resume workout, \(state)")
        .accessibilityIdentifier("resume.ring")
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
