import AppIntents
import SwiftUI
import WorkoutsKit

/// Skip / +30 s / Done set. Skip and +30 s exist only while a rest runs; Done set is always there, disabled when there
/// is nothing to check or the set is empty (the app would refuse it).
///
/// The buttons are `Button(intent:)` with the `LiveActivityIntent`s in `Shared/ActivityIntents.swift`; they run in the
/// app process and the engine's next state re-renders the activity.
struct ActivityControls: View {
    let state: WorkoutActivityState

    var body: some View {
        HStack(spacing: 8) {
            if state.isResting {
                Button(intent: SkipRestIntent()) {
                    ActivityButtonLabel(title: "Skip", symbol: "forward.end.fill", style: .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip rest")
                Button(intent: AddRestIntent(seconds: 30)) {
                    ActivityButtonLabel(title: "+30 s", symbol: "goforward.30", style: .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add 30 seconds of rest")
            }
            Button(intent: DoneSetIntent(setID: state.current?.setID ?? UUID())) {
                ActivityButtonLabel(title: "Done set", symbol: "checkmark", style: .primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done set")
            .disabled(isDoneDisabled)
        }
    }

    private var isDoneDisabled: Bool {
        guard let current = state.current else { return true }
        return current.isEmpty
    }
}

/// The capsule a control button draws; greys out when the enclosing button is disabled.
struct ActivityButtonLabel: View {
    enum Style { case primary, secondary }

    let title: String
    let symbol: String
    let style: Style

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 36)
            .foregroundStyle(style == .primary ? Color.white : ActivityStyle.accent)
            .background(
                Capsule().fill(
                    style == .primary
                        ? ActivityStyle.accent : ActivityStyle.accent.opacity(0.18)
                )
            )
            .opacity(isEnabled ? 1 : 0.5)
    }
}
