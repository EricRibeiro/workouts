import SwiftUI
import WorkoutsKit

// MARK: - Expanded

/// Leading: the glyph, next to the camera cutout.
struct ExpandedGlyphView: View {
    var body: some View {
        Image(systemName: ActivityStyle.glyph)
            .font(.title2)
            .foregroundStyle(ActivityStyle.accent)
            .accessibilityLabel("Workout")
    }
}

/// Trailing: the timer and what it counts.
struct ExpandedTimerView: View {
    let state: WorkoutActivityState

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ActivityTimerText(state: state)
                .font(.title2.weight(.semibold))
            ActivityTimerCaption(state: state)
        }
    }
}

/// Center: exercise name over "Set 3 of 4 · 27.5 lb × 8" (or "All sets done").
struct ExpandedDetailView: View {
    let state: WorkoutActivityState

    var body: some View {
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
    }
}

// MARK: - Compact and minimal

struct CompactLeadingView: View {
    var body: some View {
        Image(systemName: ActivityStyle.glyph)
            .foregroundStyle(ActivityStyle.accent)
            .accessibilityLabel("Workout")
    }
}

struct CompactTrailingView: View {
    let state: WorkoutActivityState

    var body: some View {
        ActivityTimerText(state: state)
            .foregroundStyle(state.isResting ? ActivityStyle.accent : .primary)
            .frame(maxWidth: 52)
    }
}

/// A ring that drains over the rest (drawn by the system), the glyph alone when no rest runs.
struct MinimalView: View {
    let state: WorkoutActivityState

    var body: some View {
        if let range = state.restRange() {
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
