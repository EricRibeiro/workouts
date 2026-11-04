//
//  WorkoutView.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

struct WorkoutView: View {
    /// Opens the Settings sheet, which the root view owns.
    var showSettings: () -> Void = {}
    /// Presents the active workout's cover, which the root view owns.
    var presentWorkout: () -> Void = {}
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Templates",
                systemImage: "dumbbell",
                description: Text("Your workout templates will appear here.")
            )
            .navigationTitle("Workout")
            .resumeControl()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Add", systemImage: "plus") {
                        Button("Empty Workout", systemImage: "figure.strengthtraining.traditional", action: startEmpty)
                            .accessibilityLabel("Empty Workout")
                            .accessibilityIdentifier("toolbar.add.emptyWorkout")
                    }
                    .accessibilityLabel("Add")
                    .accessibilityIdentifier("toolbar.add")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape", action: showSettings)
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("toolbar.settings")
                }
            }
        }
        .accessibilityIdentifier("screen.workout")
    }

    private func startEmpty() {
        // TODO: with a workout already running, show the "Workout in progress" sheet (Resume / Discard and Start New).
        if engine?.workout == nil { _ = try? engine?.startEmpty() }
        presentWorkout()
    }
}

#Preview {
    WorkoutView()
}
