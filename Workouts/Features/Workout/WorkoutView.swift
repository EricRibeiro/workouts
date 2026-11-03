//
//  WorkoutView.swift
//  Workouts
//

import SwiftUI

struct WorkoutView: View {
    /// Opens the Settings sheet, which the root view owns.
    var showSettings: () -> Void = {}

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Templates",
                systemImage: "dumbbell",
                description: Text("Your workout templates will appear here.")
            )
            .navigationTitle("Workout")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape", action: showSettings)
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("toolbar.settings")
                }
            }
        }
        .accessibilityIdentifier("screen.workout")
    }
}

#Preview {
    WorkoutView()
}
