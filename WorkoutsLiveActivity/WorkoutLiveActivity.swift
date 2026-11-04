import ActivityKit
import SwiftUI
import WidgetKit
import WorkoutsKit

/// The active workout's Lock Screen banner and Dynamic Island (PLAN 1.4, `DECISIONS.md` "Live Activity"). The Island is
/// drawn only on the closed display; the system decides, so nothing here branches on it.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state)
                .activityBackgroundTint(ActivityStyle.backgroundTint)
                .activitySystemActionForegroundColor(ActivityStyle.accent)
                .widgetURL(ActivityStyle.openURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedGlyphView()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTimerView(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedDetailView(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityControls(state: context.state)
                }
            } compactLeading: {
                CompactLeadingView()
            } compactTrailing: {
                CompactTrailingView(state: context.state)
            } minimal: {
                MinimalView(state: context.state)
            }
            .keylineTint(ActivityStyle.accent)
            .widgetURL(ActivityStyle.openURL)
        }
    }
}
