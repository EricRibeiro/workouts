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

/// Asks the Workout tab to push the editor for an existing template (R3-03): from a sidebar template tab's Edit. The
/// template tabs exist only at regular width and vanish when the Duo closes, so the editor (and its draft) must live on the
/// Workout tab's stack, which persists in both widths. The id makes every request distinct.
struct EditTemplateRequest: Hashable {
    let id = UUID()
    let templateID: UUID
}

/// The content of a template's sidebar tab (PLAN 3.7): its preview on its own stack. Start Workout opens the root's cover
/// (the same `StartWorkoutFlow` the preview runs, with the root's `presentWorkout`); Edit hands the template to the root,
/// which selects the Workout tab and pushes the editor there (`EditTemplateRequest`), so a fold cannot destroy the draft.
struct TemplateTab: View {
    let template: Template
    /// Presents the active workout's cover, which the root view owns.
    let presentWorkout: () -> Void
    /// Asks the root to edit a template on the Workout tab.
    let edit: (Template) -> Void

    var body: some View {
        NavigationStack {
            TemplatePreview(template: template, started: presentWorkout, edit: edit)
                .resumeControl()
        }
    }
}
