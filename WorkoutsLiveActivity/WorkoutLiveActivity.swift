import ActivityKit
import SwiftUI
import WidgetKit
import WorkoutsKit

/// The active workout's Lock Screen banner and Dynamic Island (PLAN 1.4, `DECISIONS.md` "Live Activity"). The Island is
/// drawn only on the closed display; the system decides, so nothing here branches on it except the views that read
/// `isDynamicIslandLimitedInWidth` (the closed Duo's narrow, vertical Island).
///
/// "Rest over" is `context.isStale` (the app sets `staleDate` to the rest's end and the system re-renders then, with the
/// app suspended) or an end already in the past at render time. All timers stay system-drawn.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            Self.lockScreen(state: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            let state = context.state
            let isStale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Self.expandedLeading(state: state, isStale: isStale)
                }
                DynamicIslandExpandedRegion(.trailing, priority: 1) {
                    Self.expandedTrailing(state: state, isStale: isStale)
                }
            } compactLeading: {
                Self.compactLeading(state: state, isStale: isStale)
            } compactTrailing: {
                Self.compactTrailing(state: state, isStale: isStale)
            } minimal: {
                Self.minimal(state: state, isStale: isStale)
            }
            .keylineTint(Self.keylineTint(state: state, isStale: isStale))
            .widgetURL(ActivityStyle.openURL)
        }
    }

    // The presentation bodies as plain functions, so tests can render them without WidgetKit.

    static func lockScreen(state: WorkoutActivityState, isStale: Bool) -> some View {
        LockScreenActivityView(state: state, restOver: state.isRestOver(stale: isStale))
            .activityBackgroundTint(ActivityStyle.backgroundTint)
            .activitySystemActionForegroundColor(ActivityStyle.accent)
            .widgetURL(ActivityStyle.openURL)
    }

    static func expandedLeading(state: WorkoutActivityState, isStale: Bool) -> some View {
        ExpandedControlsView(state: state, restOver: state.isRestOver(stale: isStale))
    }

    static func expandedTrailing(state: WorkoutActivityState, isStale: Bool) -> some View {
        ExpandedTimerView(state: state, restOver: state.isRestOver(stale: isStale))
    }

    static func compactLeading(state: WorkoutActivityState, isStale: Bool) -> some View {
        CompactLeadingView(state: state, restOver: state.isRestOver(stale: isStale))
    }

    static func compactTrailing(state: WorkoutActivityState, isStale: Bool) -> some View {
        CompactTrailingView(state: state, restOver: state.isRestOver(stale: isStale))
    }

    static func minimal(state: WorkoutActivityState, isStale: Bool) -> some View {
        MinimalView(state: state, restOver: state.isRestOver(stale: isStale))
    }

    static func keylineTint(state: WorkoutActivityState, isStale: Bool) -> Color {
        state.isRestOver(stale: isStale) ? ActivityStyle.ok : ActivityStyle.accent
    }
}
