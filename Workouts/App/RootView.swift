//
//  RootView.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The app shell: three tabs (sidebar-adaptable) and the Settings sheet.
struct RootView: View {
    @State private var navigation = AppNavigation()
    /// The finished workout's numbers, held until the cover has closed.
    @State private var pendingSummary: FinishSummaryItem?
    /// The summary sheet's item; presented from here (not the cover) once the cover is gone.
    @State private var finishSummary: FinishSummaryItem?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        TabView(selection: Binding(get: { navigation.selectedTab }, set: { navigation.select($0) })) {
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView(path: $navigation.historyPath)
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
        // The scrolling lists (History, Exercises) let the tab bar collapse; the Workout tab keeps it (DECISIONS).
        .tabBarMinimizeBehavior(navigation.selectedTab == .workout ? .never : .onScrollDown)
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
        .sheet(item: $finishSummary) { item in
            FinishSummaryView(summary: item.summary)
                .presentationPlacement(.center)
        }
        .fullScreenCover(
            isPresented: $navigation.isWorkoutCoverPresented,
            onDismiss: {
                finishSummary = pendingSummary
                pendingSummary = nil
            }
        ) {
            ActiveWorkoutCover(
                minimise: { navigation.minimiseWorkout() },
                onFinished: { summary in
                    pendingSummary = FinishSummaryItem(summary: summary)
                    navigation.endWorkout()
                },
                onDiscarded: { navigation.endWorkout() }
            )
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
