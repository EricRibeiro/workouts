//
//  NoteSheet.swift
//  Workouts
//

import SwiftUI

/// The one note editor: the block menu's Note (both screens), the template editor's Edit Note… and the exercise's sticky
/// note. A `Form` with one auto-focused, growing multi-line field, Cancel and Save items, and swipe-to-dismiss blocked
/// while the text differs from what it opened with. `onSave` receives the raw text; the owner trims it (a blank note
/// clears it). A throwing `onSave` or `onRemove` keeps the sheet open and shows a "Could Not Save" alert. `onRemove`
/// adds a destructive Remove row when the note being edited is not empty. The ids are `<idPrefix>.field`, `.save`,
/// `.cancel` and `.remove`, plus `<idPrefix>.sheet` on the sheet.
struct NoteSheet: View {
    let initialText: String
    let idPrefix: String
    let title: String
    /// Longest text the field keeps; nil = unlimited.
    let maxLength: Int?
    let removeTitle: String
    let onRemove: (() throws -> Void)?
    let onSave: (String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var saveError: String?
    @FocusState private var isFocused: Bool

    init(
        initialText: String,
        idPrefix: String,
        title: String = "Note",
        maxLength: Int? = nil,
        removeTitle: String = "Remove Note",
        onRemove: (() throws -> Void)? = nil,
        onSave: @escaping (String) throws -> Void
    ) {
        self.initialText = initialText
        self.idPrefix = idPrefix
        self.title = title
        self.maxLength = maxLength
        self.removeTitle = removeTitle
        self.onRemove = onRemove
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
                        .accessibilityLabel(title)
                        .accessibilityIdentifier("\(idPrefix).field")
                        .onChange(of: text) { _, new in
                            if let maxLength, new.count > maxLength { text = String(new.prefix(maxLength)) }
                        }
                }
                if let onRemove, !initialText.isEmpty {
                    Section {
                        Button(removeTitle, systemImage: "trash", role: .destructive) {
                            perform(onRemove)
                        }
                        .accessibilityIdentifier("\(idPrefix).remove")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CancelToolbarItem(id: "\(idPrefix).cancel") { dismiss() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        perform { try onSave(text) }
                    }
                    .accessibilityLabel("Save")
                    .accessibilityIdentifier("\(idPrefix).save")
                }
            }
            .alert(
                "Could Not Save",
                isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
        .interactiveDismissDisabled(text != initialText)
        .onAppear { isFocused = true }
        .accessibilityIdentifier("\(idPrefix).sheet")
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
