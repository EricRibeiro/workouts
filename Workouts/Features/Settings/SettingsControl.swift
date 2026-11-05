//
//  SettingsControl.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The Settings gear on every tab's root screen (Eric, 2026-11-04: Settings holds more than workout settings now, so it
/// should not need a trip to the Workout tab). Opens the one Settings sheet `RootView` presents. Toolbar items do not
/// inherit on push, so each tab root applies this modifier; apply it outside `resumeControl()` so the resume ring stays
/// last in its own glass group.
private struct SettingsControl: ViewModifier {
    @Environment(AppNavigation.self) private var navigation: AppNavigation?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if let navigation {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Settings", systemImage: "gearshape") { navigation.openSettings() }
                            .accessibilityLabel("Settings")
                            .accessibilityIdentifier("toolbar.settings")
                    }
                }
            }
    }
}

extension View {
    /// Adds the Settings gear to this tab root's toolbar.
    func settingsControl() -> some View {
        modifier(SettingsControl())
    }
}
