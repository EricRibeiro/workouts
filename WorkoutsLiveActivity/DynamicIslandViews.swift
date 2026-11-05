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

/// Leading: the ring and glyph in a tight ~36 pt square next to the camera cutout.
struct ExpandedGlyphView: View {
    let state: WorkoutActivityState
    let restOver: Bool

    var body: some View {
        ActivityRing(state: state, restOver: restOver)
            .font(.title3)
            .frame(width: 36, height: 36)
            .fixedSize()
    }
}

/// Trailing: the timer and what it counts.
struct ExpandedTimerView: View {
    let state: WorkoutActivityState
    let restOver: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ActivityTimerText(state: state, restOver: restOver)
                .font(.title2.weight(.semibold))
            ActivityTimerCaption(state: state, restOver: restOver)
        }
    }
}

/// Center: exercise name over "Set 3 of 5 · 27.5 kg × 8" ("Rest over · Set 3 · 27.5 kg × 8", "All sets done").
struct ExpandedDetailView: View {
    let state: WorkoutActivityState
    let restOver: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(state.current?.exerciseName ?? state.workoutName)
                .font(.headline)
                .lineLimit(1)
            Text(state.activityDetailText(restOver: restOver))
                .font(.subheadline)
                .foregroundStyle(restOver ? ActivityStyle.ok : .secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bottom: the rest controls while a rest runs; otherwise (also once it is over) the done-set control over "5 of 14 sets".
struct ExpandedBottomView: View {
    let state: WorkoutActivityState
    let restOver: Bool

    var body: some View {
        VStack(spacing: 4) {
            ActivityControls(state: state, restOver: restOver)
            if !state.isRestRunning(restOver: restOver), let text = state.setsProgressText {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Compact and minimal

/// The closed iPhone Duo's Island is narrow and vertical (`isDynamicIslandLimitedInWidth`): the compact leading side
/// then carries the whole minimal view (ring and glyph) and the trailing side is empty. Full width keeps the glyph
/// (ring and glyph while a rest runs) leading and the number trailing.
struct CompactLeadingView: View {
    let state: WorkoutActivityState
    let restOver: Bool

    @Environment(\.isDynamicIslandLimitedInWidth) private var isLimited

    var body: some View {
        if isLimited {
            MinimalView(state: state, restOver: restOver)
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
