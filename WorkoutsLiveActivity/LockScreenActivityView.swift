import SwiftUI
import WidgetKit
import WorkoutsKit

/// The Lock Screen / StandBy banner, as plain rows so nothing competes for width: the exercise name, then the set
/// detail with the timer at the trailing edge, a rest progress bar while resting, then the controls.
struct LockScreenActivityView: View {
    let state: WorkoutActivityState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(state.current?.exerciseName ?? state.workoutName)
                    .font(.headline)
                    .lineLimit(1)
                Text(state.activityDetailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                ActivityTimerCaption(state: state)
                ActivityTimerText(state: state, alignment: .leading)
                    .font(.title3.weight(.semibold))
                if let range = state.restRange() {
                    ProgressView(timerInterval: range, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(ActivityStyle.accent)
                    .accessibilityLabel("Rest progress")
                }
                Spacer(minLength: 0)
            }
            ActivityControls(state: state)
        }
        .padding(16)
    }
}

extension WorkoutActivityState {
    /// "Set 3 of 4 · 27.5 lb × 8", "Set 3 of 4" without values, "All sets done" when nothing is left.
    var activityDetailText: String {
        guard let current else { return "All sets done" }
        return current.detailText.isEmpty
            ? current.progressText : "\(current.progressText) · \(current.detailText)"
    }
}

#if DEBUG
    #Preview("Lock Screen", as: .content, using: WorkoutActivityAttributes(workoutID: UUID())) {
        WorkoutLiveActivity()
    } contentStates: {
        WorkoutActivityState.sampleResting
        WorkoutActivityState.sampleLogging
        WorkoutActivityState.sampleAllDone
        WorkoutActivityState.sampleLongNames
    }
#endif
