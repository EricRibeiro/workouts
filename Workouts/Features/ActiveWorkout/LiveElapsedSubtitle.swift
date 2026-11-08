import SwiftUI
import WorkoutsKit

/// The navigation subtitle "Nov 4 · 12:34". `.navigationSubtitle` hands UIKit a resolved string, so a self-updating
/// `.timer` Text never ticks there; this re-resolves it every second, and only this modifier's body re-evaluates.
private struct LiveElapsedSubtitle: ViewModifier {
    let startedAt: Date

    func body(content: Content) -> some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let started = startedAt.formatted(.dateTime.month(.abbreviated).day())
            let elapsed = ClockFormat.clock(seconds: context.date.timeIntervalSince(startedAt))
            content.navigationSubtitle(Text(verbatim: "\(started) · \(elapsed)"))
        }
    }
}

extension View {
    /// Shows "Nov 4 · 12:34" under the navigation title, the elapsed time counting up since `startedAt`.
    func liveElapsedSubtitle(startedAt: Date) -> some View {
        modifier(LiveElapsedSubtitle(startedAt: startedAt))
    }
}
