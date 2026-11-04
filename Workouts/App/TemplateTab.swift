//
//  TemplateTab.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// Asks the Workout tab to push the new-template editor (PLAN 3.7): from a sidebar section's "New Template" action.
/// `folderID` is the section's folder (nil: unfiled). The id makes every request distinct, so asking twice pushes twice.
struct NewTemplateRequest: Hashable {
    let id = UUID()
    let folderID: UUID?
}

/// The content of a template's sidebar tab (PLAN 3.7): its preview on its own stack. Start Workout opens the root's cover
/// (the same `StartWorkoutFlow` the preview runs, with the root's `presentWorkout`); Edit pushes the editor on this stack,
/// under which the preview stays, so Save and Cancel return to it.
struct TemplateTab: View {
    let template: Template
    /// Presents the active workout's cover, which the root view owns.
    let presentWorkout: () -> Void
    @State private var editing: Template?

    var body: some View {
        NavigationStack {
            TemplatePreview(template: template, started: presentWorkout, edit: { editing = $0 })
                .navigationDestination(item: $editing) { TemplateEditor(template: $0) }
                .resumeControl()
        }
    }
}
