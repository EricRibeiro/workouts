//
//  TemplateUpdateDialog.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The "Update Template?" question after Finish (`active-workout.md` section 3): which workout, which template and how it
/// differs. Plain values, never the models, so a deleted template cannot be read through it.
struct TemplateUpdatePrompt: Identifiable {
    let id = UUID()
    let workoutID: UUID
    let templateName: String
    let kind: TemplateUpdate.Kind
}

extension View {
    /// Presents the "Update Template?" confirmation for `prompt` and reports the answer through `apply`. The workout is
    /// saved either way; dismissing the dialog keeps the original template.
    func templateUpdateDialog(
        _ prompt: Binding<TemplateUpdatePrompt?>,
        apply: @escaping (TemplateUpdate.Choice, TemplateUpdatePrompt) -> Void
    ) -> some View {
        confirmationDialog(
            "Update Template?",
            isPresented: Binding(get: { prompt.wrappedValue != nil }, set: { if !$0 { prompt.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: prompt.wrappedValue
        ) { prompt in
            if prompt.kind == .structure {
                Button("Update Values Only") { apply(.valuesOnly, prompt) }
                    .accessibilityIdentifier("updateTemplate.valuesOnly")
                Button("Update Template and Values", role: .destructive) { apply(.templateAndValues, prompt) }
                    .accessibilityIdentifier("updateTemplate.templateAndValues")
            } else {
                Button("Update Template") { apply(.valuesOnly, prompt) }
                    .accessibilityIdentifier("updateTemplate.update")
            }
            Button("Keep Original Template", role: .cancel) {}
                .accessibilityIdentifier("updateTemplate.keep")
        } message: { prompt in
            switch prompt.kind {
            case .structure:
                Text(
                    "You changed the exercises or sets compared with “\(prompt.templateName)”. Update only its weights and reps, or make the template match this workout."
                )
            case .valuesOnly, .none:
                Text(
                    "The weights or reps differ from “\(prompt.templateName)”. Update the template with the new values?"
                )
            }
        }
    }
}
