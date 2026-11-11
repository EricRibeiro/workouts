import SwiftUI
import WidgetKit
import WorkoutsKit

/// The Lock Screen / StandBy banner, as plain rows so nothing competes for width: the exercise name and set line, the
/// timer row (the caption and time; "Rest over" in the ok colour once it ends), the workout's set progress (the
/// banner's one linear bar), then the controls. It pins the dark colour scheme (see ``ActivityStyle``).
struct LockScreenActivityView: View {
    let state: WorkoutActivityState
    let restOver: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(state.current?.exerciseName ?? state.workoutName)
                    .font(.headline)
                    .lineLimit(1)
                // "Rest over" is said by the timer row below, so the set line stays plain here.
                Text(state.activityDetailText)
                    .font(.subheadline)
                    .foregroundStyle(ActivityStyle.secondaryText)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            timerRow
            if state.setsTotal > 0 {
                HStack(spacing: 8) {
                    ActivityProgressBar(
                        fraction: Double(min(state.setsDone, state.setsTotal)) / Double(state.setsTotal)
                    )
                    .accessibilityHidden(true)  // the caption says it
                    if let text = state.setsProgressText {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(ActivityStyle.secondaryText)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ActivityControls(state: state, restOver: restOver)
        }
        .padding(16)
        .foregroundStyle(ActivityStyle.primaryText)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var timerRow: some View {
        HStack(spacing: 8) {
            if restOver {
                Label("Rest over", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ActivityStyle.ok)
                Spacer(minLength: 0)
                ActivityTimerText(state: state, restOver: true, alignment: .trailing)
                    .font(.subheadline)
                    .foregroundStyle(ActivityStyle.secondaryText)
            } else {
                ActivityTimerCaption(state: state)
                ActivityTimerText(state: state, alignment: .leading)
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 0)
            }
        }
    }
}

/// The set-progress bar: an explicit track and the accent fill, since the system's linear `ProgressView` draws its track
/// in a semantic fill that could follow the device's light appearance.
struct ActivityProgressBar: View {
    /// 0...1.
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(ActivityStyle.track)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(ActivityStyle.accent)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
    }
}

extension WorkoutActivityState {
    /// "Set 3 of 4 · 27.5 lb × 8", "Set 3 of 4" without values, "All sets done" when nothing is left.
    var activityDetailText: String { activityDetailText(restOver: false) }

    /// Like ``activityDetailText``; once the rest is over it leads with "Rest over · Set 3 · 27.5 lb × 8" (the next set
    /// as the rest-end notification words it).
    func activityDetailText(restOver: Bool) -> String {
        guard let current else { return restOver ? "Rest over" : "All sets done" }
        if restOver { return "Rest over · \(current.nextSetText)" }
        return current.detailText.isEmpty
            ? current.progressText : "\(current.progressText) · \(current.detailText)"
    }

    /// "5 of 14 sets"; nil when the workout has no sets.
    var setsProgressText: String? {
        setsTotal > 0 ? "\(min(setsDone, setsTotal)) of \(setsTotal) sets" : nil
    }
}
