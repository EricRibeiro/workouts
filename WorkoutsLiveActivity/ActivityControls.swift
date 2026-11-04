import SwiftUI
import WorkoutsKit

/// Skip / +30 s / Done set. Skip and +30 s exist only while a rest runs; Done set is always there, disabled when there
/// is nothing to check or the set is empty (the app would refuse it).
///
/// The buttons are placeholders until task 1.5 adds the `LiveActivityIntent`s: a plain `Button` in a widget does
/// nothing, which is the intended no-op for now.
struct ActivityControls: View {
    let state: WorkoutActivityState

    var body: some View {
        HStack(spacing: 8) {
            if state.isResting {
                // 1.5: Button(intent: SkipRestIntent())
                ActivityButton(title: "Skip", label: "Skip rest", symbol: "forward.end.fill", style: .secondary) {}
                // 1.5: Button(intent: AddRestIntent(seconds: 30))
                ActivityButton(
                    title: "+30 s",
                    label: "Add 30 seconds of rest",
                    symbol: "goforward.30",
                    style: .secondary
                ) {}
            }
            // 1.5: Button(intent: CompleteSetIntent(setID: current.setID))
            ActivityButton(title: "Done set", label: "Done set", symbol: "checkmark", style: .primary) {}
                .disabled(isDoneDisabled)
        }
    }

    private var isDoneDisabled: Bool {
        guard let current = state.current else { return true }
        return current.isEmpty
    }
}

struct ActivityButton: View {
    enum Style { case primary, secondary }

    let title: String
    let label: String
    let symbol: String
    let style: Style
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
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
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
