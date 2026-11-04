//
//  StickyNoteView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The sticky note block of the exercise detail and the logging pane (task 4.5): the note on a yellow band with an Edit
/// button, or an Add button when there is none. The note belongs to the exercise, so it is saved the moment the editor
/// saves, not with a template or workout.
struct StickyNoteView: View {
    let exerciseID: UUID

    @Query private var notes: [StickyNote]
    @State private var isEditing = false

    init(exerciseID: UUID) {
        self.exerciseID = exerciseID
        _notes = Query(filter: #Predicate<StickyNote> { $0.exerciseID == exerciseID })
    }

    private var text: String? {
        notes.first(where: { !$0.text.isEmpty })?.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let text {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Sticky note: \(text)")
                    .accessibilityIdentifier("exerciseDetail.stickyNote.text")
            }
            Button {
                isEditing = true
            } label: {
                Label(
                    text == nil ? "Add Sticky Note" : "Edit Sticky Note",
                    systemImage: text == nil ? "note.text.badge.plus" : "pencil"
                )
                .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("exerciseDetail.stickyNote.edit")
        }
        .padding(text == nil ? 0 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if text != nil {
                RoundedRectangle(cornerRadius: 12).fill(Color.stickyNote)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exerciseDetail.stickyNote")
        .sheet(isPresented: $isEditing) {
            StickyNoteEditor(exerciseID: exerciseID, initialText: text ?? "")
                .presentationPlacement(.center)
        }
    }
}

/// The small editor sheet: a multiline `TextEditor`, Save and Cancel, and Remove when a note exists.
struct StickyNoteEditor: View {
    let exerciseID: UUID
    let initialText: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var draft: String
    @State private var saveError: String?
    @State private var removals = 0

    init(exerciseID: UUID, initialText: String) {
        self.exerciseID = exerciseID
        self.initialText = initialText
        _draft = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draft)
                        .frame(minHeight: 140)
                        .accessibilityLabel("Sticky note")
                        .accessibilityIdentifier("stickyNote.text")
                        .onChange(of: draft) { _, new in
                            if new.count > StickyNotes.maxLength { draft = String(new.prefix(StickyNotes.maxLength)) }
                        }
                } footer: {
                    Text("Shown on this exercise in every template")
                }
                if !initialText.isEmpty {
                    Section {
                        Button("Remove Sticky Note", systemImage: "trash", role: .destructive) {
                            removals += 1
                            perform { try StickyNotes.clear(exerciseID, in: context) }
                        }
                        .accessibilityIdentifier("stickyNote.remove")
                    }
                }
            }
            .navigationTitle("Sticky Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("stickyNote.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        perform { try StickyNotes.set(draft, for: exerciseID, in: context) }
                    }
                    .accessibilityIdentifier("stickyNote.save")
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
        .interactiveDismissDisabled(draft != initialText)
        .sensoryFeedback(.warning, trigger: removals)
        .accessibilityIdentifier("stickyNote.editor")
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
