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
            LockScreenActivityView(
                state: context.state,
                restOver: context.state.isRestOver(stale: context.isStale)
            )
            .activityBackgroundTint(ActivityStyle.backgroundTint)
            .activitySystemActionForegroundColor(ActivityStyle.accent)
            .widgetURL(ActivityStyle.openURL)
        } dynamicIsland: { context in
            let state = context.state
            let restOver = state.isRestOver(stale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedControlsView(state: state, restOver: restOver)
                }
                DynamicIslandExpandedRegion(.trailing, priority: 1) {
                    ExpandedTimerView(state: state, restOver: restOver)
                }
            } compactLeading: {
                CompactLeadingView(state: state, restOver: restOver)
            } compactTrailing: {
                CompactTrailingView(state: state, restOver: restOver)
            } minimal: {
                MinimalView(state: state, restOver: restOver)
            }
            .keylineTint(restOver ? ActivityStyle.ok : ActivityStyle.accent)
            .widgetURL(ActivityStyle.openURL)
        }
    }
}
