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
                .accessibilityLabel("Skip rest")
                Button(intent: AddRestIntent(seconds: 30)) {
                    ActivityControlLabel(title: "+30 s", symbol: "goforward.30")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Add 30 seconds of rest")
            }
            Button(intent: DoneSetIntent(setID: state.current?.setID ?? UUID())) {
                ActivityControlLabel(title: "Done", symbol: "checkmark")
            }
            .buttonStyle(.borderedProminent)
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
