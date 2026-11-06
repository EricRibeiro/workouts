//
//  DismissSheetsOnWorkoutOpen.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

private struct DismissSheetsOnWorkoutOpen: ViewModifier {
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    let dismiss: () -> Void

    func body(content: Content) -> some View {
        content
            // The Live Activity or the rest notification opens the workout cover, which cannot present over a sheet: every
            // screen that owns one closes it when `openActiveWorkout()` asks.
            .onChange(of: navigation?.dismissSheetsRequest ?? 0) { dismiss() }
    }
}

extension View {
    /// Runs `dismiss` (which should close this screen's sheets) when the running workout is opened from outside the app.
    func dismissSheetsOnWorkoutOpen(_ dismiss: @escaping () -> Void) -> some View {
        modifier(DismissSheetsOnWorkoutOpen(dismiss: dismiss))
    }
}
