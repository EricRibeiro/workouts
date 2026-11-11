import SwiftUI

/// Colours and constants shared by the Live Activity views. The extension has no asset catalog of its own and cannot see
/// the app's, so the app's lime (`#C4F861`) is spelled out here. Like the app, the Live Activity is dark-only: the
/// Island is always black and the Lock Screen banner pins a dark card and the dark colour scheme whatever the device's
/// appearance, so the lime always sits on a dark surface.
enum ActivityStyle {
    /// The app's accent lime.
    static let accent = Color(red: 0xC4 / 255, green: 0xF8 / 255, blue: 0x61 / 255)
    /// "Rest over": the rest finished and the next set is due. The same lime as `accent`, as in the app.
    static let ok = accent
    /// A glyph or label on an `accent` fill.
    static let onAccent = Color.black
    static let glyph = "dumbbell.fill"
    /// The Lock Screen banner's card: the dark system secondary background, fixed so a light device appearance does not
    /// turn it into a light-gray card.
    static let backgroundTint = Color(white: 0.11)
    /// Opened by tapping the banner or the Island. The app registers the `workouts` scheme (Workouts/Info.plist) and `RootView.onOpenURL` shows the active workout.
    static let openURL = URL(string: "workouts://workout")
}
