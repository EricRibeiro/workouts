//
//  ExercisesView.swift
//  Workouts
//

import SwiftUI

struct ExercisesView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Exercises",
                systemImage: "figure.strengthtraining.traditional",
                description: Text("The exercise library will appear here.")
            )
            .navigationTitle("Exercises")
        }
        .accessibilityIdentifier("screen.exercises")
    }
}

#Preview {
    ExercisesView()
}
