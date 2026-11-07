import SwiftUI
import WidgetKit
import WorkoutsKit

// MARK: - Ring

/// The Island's one glyph: a ring that drains over the rest (drawn by the system) around the dumbbell, a full `ok`
/// ring around a checkmark once the rest is over, and the dumbbell alone when no rest exists.
struct ActivityRing: View {
    let state: WorkoutActivityState
    let restOver: Bool

    var body: some View {
        if restOver {
            ProgressView(value: 1) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: "checkmark")
            }
            .progressViewStyle(.circular)
            .tint(ActivityStyle.ok)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest over")
        } else if let range = state.restRange() {
            ProgressView(timerInterval: range, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: ActivityStyle.glyph)
            }
            .progressViewStyle(.circular)
            .tint(ActivityStyle.accent)
            .activityTimerAccessibility(for: state)
        } else {
            Image(systemName: ActivityStyle.glyph)
                .foregroundStyle(ActivityStyle.accent)
                .accessibilityLabel("Workout")
        }
    }
}

// MARK: - Expanded

/// Height of the expanded Island's one row: the circular buttons and the time share it, both centred in it.
private let expandedRowHeight: CGFloat = 48

/// Leading: Apple-style circular buttons. Skip and +30 s while a rest runs; otherwise (no rest, or it is over) one
/// accent-filled Done.
struct ExpandedControlsView: View {
    let state: WorkoutActivityState
    let restOver: Bool

    var body: some View {
        IslandControls(state: state, restOver: restOver)
            .frame(height: expandedRowHeight)
    }
}

/// Trailing: one large time, accent-tinted (ok green once the rest is over): the rest countdown while one runs, else
/// the elapsed workout time. Shrinks before it truncates so "1:00:20" always shows whole.
struct ExpandedTimerView: View {
    let state: WorkoutActivityState
    let restOver: Bool

    var body: some View {
        ActivityTimerText(state: state, restOver: restOver)
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            .foregroundStyle(restOver ? ActivityStyle.ok : ActivityStyle.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, minHeight: expandedRowHeight, alignment: .trailing)
    }
}

// MARK: - Compact and minimal

/// The closed iPhone Duo's Island is narrow and vertical (`isDynamicIslandLimitedInWidth`): the compact leading side
/// then carries the whole presentation, stacked like Apple Fitness's: the minimal view (ring and glyph) over a small
/// ticking time (rest countdown, else elapsed; none once the rest is over, the ok checkmark ring says it) and the
/// trailing side is empty. Full width keeps the glyph (ring and glyph while a rest runs) leading and the number
/// trailing.
struct CompactLeadingView: View {
    let state: WorkoutActivityState
    let restOver: Bool

    @Environment(\.isDynamicIslandLimitedInWidth) private var isLimited

    var body: some View {
        CompactLeadingContent(state: state, restOver: restOver, isLimited: isLimited)
    }
}

/// ``CompactLeadingView``'s drawing with the width limit as a plain value, so snapshot tests can render the closed
/// Duo's narrow stack (`isDynamicIslandLimitedInWidth` is get-only and cannot be set in the environment).
struct CompactLeadingContent: View {
    let state: WorkoutActivityState
    let restOver: Bool
    let isLimited: Bool

    var body: some View {
        if isLimited {
            VStack(spacing: 1) {
                MinimalView(state: state, restOver: restOver)
                if !restOver {
                    ActivityCompactTimerText(state: state)
                }
            }
        } else if state.isRestRunning(restOver: restOver) {
            ActivityRing(state: state, restOver: false)
        } else {
            Image(systemName: ActivityStyle.glyph)
                .foregroundStyle(ActivityStyle.accent)
                .accessibilityLabel("Workout")
        }
    }
}

/// Rest countdown while resting, a checkmark once the rest is over, else the workout's elapsed time. Empty when the
/// Island is limited in width (the leading side carries everything).
struct CompactTrailingView: View {
    let state: WorkoutActivityState
    let restOver: Bool

    @Environment(\.isDynamicIslandLimitedInWidth) private var isLimited

    var body: some View {
        CompactTrailingContent(state: state, restOver: restOver, isLimited: isLimited)
    }
}

/// ``CompactTrailingView``'s drawing with the width limit as a plain value (see ``CompactLeadingContent``).
struct CompactTrailingContent: View {
    let state: WorkoutActivityState
    let restOver: Bool
    let isLimited: Bool

    var body: some View {
        if isLimited {
            EmptyView()
        } else if restOver {
            Image(systemName: "checkmark")
                .foregroundStyle(ActivityStyle.ok)
                .accessibilityLabel("Rest over")
        } else {
            ActivityTimerText(state: state)
                .foregroundStyle(state.isResting ? ActivityStyle.accent : .primary)
                .frame(maxWidth: 52)
        }
    }
}

/// A ring that drains over the rest (drawn by the system), a checkmark ring in the ok colour once it is over, the
/// glyph alone when no rest runs.
struct MinimalView: View {
    let state: WorkoutActivityState
    let restOver: Bool

    var body: some View {
        ActivityRing(state: state, restOver: restOver)
    }
}
