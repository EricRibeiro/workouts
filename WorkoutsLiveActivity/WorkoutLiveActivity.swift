import ActivityKit
import SwiftUI
import WidgetKit
import WorkoutsKit

/// Stub presentations: exercise name plus the rest countdown (or elapsed time). The real layouts are PLAN task 1.4.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            StubActivityContent(state: context.state)
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.current?.exerciseName ?? context.state.workoutName)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StubTimer(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "dumbbell")
            } compactTrailing: {
                StubTimer(state: context.state)
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "dumbbell")
            }
        }
    }
}

private struct StubActivityContent: View {
    let state: WorkoutActivityState

    var body: some View {
        HStack {
            Text(state.current?.exerciseName ?? state.workoutName)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            StubTimer(state: state)
        }
    }
}

private struct StubTimer: View {
    let state: WorkoutActivityState

    var body: some View {
        if let restEndsAt = state.restEndsAt, restEndsAt > .now {
            Text(timerInterval: .now...restEndsAt, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else {
            Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}
