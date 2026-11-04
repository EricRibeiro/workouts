//
//  ExercisePane.swift
//  Workouts
//

import SwiftUI

/// The logging screen's secondary pane on regular width (task 2.10): the focused exercise. A placeholder until the exercise
/// detail (4.5) supplies video, instructions, Previous, records and the sticky note.
struct ExercisePane: View {
    /// The focused exercise's name; nil when the workout has no exercise.
    let exerciseName: String?

    var body: some View {
        Group {
            if let exerciseName {
                ContentUnavailableView(
                    exerciseName,
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("Details arrive with the exercise detail")
                )
            } else {
                ContentUnavailableView(
                    "No exercise selected",
                    systemImage: "figure.strengthtraining.traditional"
                )
            }
        }
        .accessibilityIdentifier("cover.exercisePane")
    }
}

#Preview("Exercise") {
    ExercisePane(exerciseName: "Bench Press")
}

#Preview("Empty") {
    ExercisePane(exerciseName: nil)
}
