//
//  NoteSheet.swift
//  Workouts
//

import SwiftUI

/// The small "Note" sheet shared by the block menu's Note (both screens) and the template editor's Edit Note…: a `Form`
/// with one multi-line field, Cancel and Save items, and swipe-to-dismiss blocked while the text differs from what it
/// opened with. `onSave` receives the raw text; the owner trims it (a blank note clears it). The ids are
/// `<idPrefix>.field`, `.save` and `.cancel`, plus `<idPrefix>.sheet` on the sheet.
struct NoteSheet: View {
    let initialText: String
    let idPrefix: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(initialText: String, idPrefix: String, onSave: @escaping (String) -> Void) {
        self.initialText = initialText
        self.idPrefix = idPrefix
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Note", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                        .focused($isFocused)
                        .accessibilityLabel("Note")
                        .accessibilityIdentifier("\(idPrefix).field")
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("\(idPrefix).cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        onSave(text)
                        dismiss()
                    }
                    .accessibilityLabel("Save")
                    .accessibilityIdentifier("\(idPrefix).save")
                }
            }
        }
        .interactiveDismissDisabled(text != initialText)
        .onAppear { isFocused = true }
        .accessibilityIdentifier("\(idPrefix).sheet")
    }
}
