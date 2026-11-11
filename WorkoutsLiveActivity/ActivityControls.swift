import AppIntents
import SwiftUI
import WorkoutsKit

/// Skip / +30 s / Done set. Skip and +30 s exist only while a rest is running (not once it is over); Done set is always there,
/// disabled when there is nothing to check or the set is empty (the app would refuse it).
///
/// The buttons are `Button(intent:)` with the `LiveActivityIntent`s in `Shared/ActivityIntents.swift`; they run in the
/// app process and the engine's next state re-renders the activity. They use the system bordered styles with a tint
/// (not hand-drawn capsules) so StandBy night mode can recolour them.
struct ActivityControls: View {
    let state: WorkoutActivityState
    /// The rest ended: Skip and +30 s no longer apply, so only Done set remains.
    var restOver = false

    var body: some View {
        HStack(spacing: 8) {
            if state.isRestRunning(restOver: restOver) {
                Button(intent: SkipRestIntent()) {
                    ActivityControlLabel(title: "Skip", symbol: "forward.end.fill")
                }
                .buttonStyle(.bordered)
                .foregroundStyle(ActivityStyle.accent)
                .accessibilityLabel("Skip rest")
                Button(intent: AddRestIntent(seconds: 30)) {
                    ActivityControlLabel(title: "+30 s", symbol: "goforward.30")
                }
                .buttonStyle(.bordered)
                .foregroundStyle(ActivityStyle.accent)
                .accessibilityLabel("Add 30 seconds of rest")
            }
            Button(intent: DoneSetIntent(setID: state.current?.setID ?? UUID())) {
                ActivityControlLabel(title: "Done", symbol: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(ActivityStyle.onAccent)
            .accessibilityLabel("Done set")
            .disabled(isDoneDisabled)
        }
        .buttonBorderShape(.capsule)
        .tint(ActivityStyle.accent)
    }

    private var isDoneDisabled: Bool {
        guard let current = state.current else { return true }
        return current.isEmpty
    }
}

/// A control button's content: symbol and title filling the button, one line.
struct ActivityControlLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 28)
    }
}

/// The expanded Island's controls, drawn like Apple's Workout app: round buttons with a white symbol. Skip and +30 s
/// (dark gray) while a rest runs; otherwise one Done set in the accent colour. The same `LiveActivityIntent`s as
/// ``ActivityControls``.
struct IslandControls: View {
    let state: WorkoutActivityState
    let restOver: Bool

    var body: some View {
        HStack(spacing: 10) {
            if state.isRestRunning(restOver: restOver) {
                Button(intent: SkipRestIntent()) {
                    IslandCircleLabel(symbol: "forward.end", fill: Self.gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip rest")
                Button(intent: AddRestIntent(seconds: 30)) {
                    IslandCircleLabel(symbol: "goforward.30", fill: Self.gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add 30 seconds of rest")
            } else {
                Button(intent: DoneSetIntent(setID: state.current?.setID ?? UUID())) {
                    IslandCircleLabel(
                        symbol: "checkmark",
                        fill: ActivityStyle.accent,
                        symbolColor: ActivityStyle.onAccent
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done set")
                .disabled(state.current?.isEmpty ?? true)
            }
        }
    }

    private static let gray = Color(white: 0.22)
}

/// A filled circle with a centred symbol, white unless the fill is the accent (then `onAccent`).
struct IslandCircleLabel: View {
    let symbol: String
    let fill: Color
    var symbolColor: Color = .white

    var body: some View {
        Image(systemName: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(symbolColor)
            .frame(width: 48, height: 48)
            .background(fill, in: Circle())
            .contentShape(Circle())
    }
}
