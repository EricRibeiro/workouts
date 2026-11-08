//
//  SetTableNotes.swift
//  Workouts
//

import SwiftUI

/// The block's own note under its name (secondary text). With `onEdit` it is a button that opens the note editor.
struct SetTableNoteLine: View {
    let text: String
    var identifier: String
    var onEdit: (() -> Void)?

    var body: some View {
        if let onEdit {
            Button(action: onEdit) { line }
                .buttonStyle(.plain)
                .accessibilityLabel("Note: \(text)")
                .accessibilityHint("Edits the note")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier(identifier)
        } else {
            line
                .accessibilityIdentifier(identifier)
        }
    }

    private var line: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
    }
}
