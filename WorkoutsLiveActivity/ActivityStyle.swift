import SwiftUI

/// Colours and constants shared by the Live Activity views. The app's asset catalog is not visible to the extension, so
/// these are system colours; the accent matches the app's blue.
enum ActivityStyle {
    static let accent = Color.blue
    /// "Rest over": the rest finished and the next set is due.
    static let ok = Color.green
    static let glyph = "dumbbell.fill"
    /// The Lock Screen banner uses the system secondary background so text styles adapt to light and dark.
    static let backgroundTint = Color(.secondarySystemBackground).opacity(0.85)
    /// Opened by tapping the banner or the Island. The app registers the `workouts` scheme (Workouts/Info.plist) and `RootView.onOpenURL` shows the active workout.
    static let openURL = URL(string: "workouts://workout")
}
