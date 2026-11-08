//
//  ExercisePane.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The logging screen's secondary pane on regular width (tasks 2.10, 4.5): the focused exercise's detail, embedded (media
/// card, the About, History, Charts and Records segments), following the focus. Shared by the
/// logging screen, the past-workout editor and the template editor.
struct ExercisePane: View {
    /// The focused exercise's name; nil when the workout has no exercise.
    let exerciseName: String?
    /// The focused exercise's id (`SetTableSection.exerciseID`). Optional so older call sites keep compiling; without it the
    /// pane falls back to the library or custom exercise with exactly this name.
    var exerciseID: UUID?

    @Environment(ExerciseStore.self) private var store

    private var resolvedID: UUID? {
        if let exerciseID { return exerciseID }
        guard let exerciseName else { return nil }
        return store.all().first { $0.name == exerciseName }?.id
    }

    var body: some View {
        Group {
            if let id = resolvedID {
                ExerciseDetailView(exerciseID: id, embedded: true)
                    .id(id)
            } else if let exerciseName {
                ContentUnavailableView(
                    exerciseName,
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("This exercise is no longer available")
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

#if DEBUG
    /// The gallery host: the pane on Barbell Bench Press from the sample history, in its own stack like the regular-width
    /// secondary pane.
    struct ExercisePaneDemo: View {
        var body: some View {
            ExercisePane(exerciseName: "Barbell Bench Press")
        }
    }

    #Preview("Exercise") {
        PreviewGallery.host("ExercisePane")
    }
#endif
