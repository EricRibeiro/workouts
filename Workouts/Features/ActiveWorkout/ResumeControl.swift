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
                        label: Text("Resume workout")
                    )
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                }
            }
        }
        .accessibilityLabel("Resume workout, \(state)")
        .accessibilityIdentifier("resume.ring")
        // The engine keeps an over rest for a few seconds (the flash); with the cover closed nothing else forgets it.
        .task(id: timer.endsAt) {
            now = .now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
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

/// The sidebar's additive card (`tabViewSidebarBottomBar`): workout name, elapsed time, the rest countdown while one runs,
/// and Skip. Tapping it restores the cover. Takes the engine and navigation as parameters because the bar's content does
/// not reliably see the root's environment.
struct ResumeCard: View {
    let engine: ActiveWorkoutEngine?
    let navigation: AppNavigation
    @State private var restoreCount = 0

    var body: some View {
        if let engine, let workout = engine.workout, !navigation.isWorkoutCoverPresented {
            let timer = engine.restTimer
            HStack(spacing: 8) {
                Button {
                    restoreCount += 1
                    navigation.presentWorkout()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(workout.startedAt, style: .timer)
                            if let endsAt = timer.endsAt, endsAt > .now {
                                Text("·")
                                Text(timerInterval: Date.now...endsAt, countsDown: true)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume workout, \(workout.name)")
                .accessibilityIdentifier("resume.card")
                if timer.isActive {
                    Button("Skip rest", systemImage: "forward.end") { try? engine.skipRest() }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Skip rest")
                        .accessibilityIdentifier("resume.card.skip")
                }
            }
            .padding(10)
            .background(.quaternary, in: .rect(cornerRadius: 12))
            .sensoryFeedback(.selection, trigger: restoreCount)
        }
    }
}
