//
//  RootView.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The app shell: three tabs (sidebar-adaptable) and the Settings sheet.
struct RootView: View {
    @State private var navigation = AppNavigation()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        TabView(selection: Binding(get: { navigation.selectedTab }, set: { navigation.select($0) })) {
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView()
            }
            .accessibilityIdentifier("tab.history")

            Tab("Workout", systemImage: "dumbbell", value: AppTab.workout) {
                WorkoutView(
                    showSettings: { navigation.openSettings() },
                    presentWorkout: { navigation.presentWorkout() }
                )
            }
            .accessibilityIdentifier("tab.workout")

            Tab("Exercises", systemImage: "figure.strengthtraining.traditional", value: AppTab.exercises) {
                ExercisesView()
            }
            .accessibilityIdentifier("tab.exercises")
        }
        .tabViewStyle(.sidebarAdaptable)
        .defaultAdaptableTabBarPlacement(.sidebar)
        .tabViewSidebarBottomBar {
            if horizontalSizeClass == .regular {
                Button("Settings", systemImage: "gearshape") { navigation.openSettings() }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("sidebar.settings")
            }
        }
        .sheet(isPresented: $navigation.isSettingsPresented) {
            SettingsView()
                .presentationPlacement(.center)
        }
        .fullScreenCover(isPresented: $navigation.isWorkoutCoverPresented) {
            ActiveWorkoutCover(minimise: { navigation.minimiseWorkout() })
        }
        #if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-openWorkoutCover") {
                    navigation.presentWorkout()
                }
            }
        #endif
    }
}

#Preview {
    RootView()
}
