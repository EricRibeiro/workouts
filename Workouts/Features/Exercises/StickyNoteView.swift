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

    @Environment(\.modelContext) private var context
    @Query private var notes: [StickyNote]
    @State private var isEditing = false
    @State private var removals = 0

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
                .foregroundStyle(.primary)
                // 44 pt minimum hit height (the audit measured 19.7 pt); the text stays leading-aligned.
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
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
            NoteSheet(
                stickyNoteFor: exerciseID,
                initialText: text ?? "",
                in: context,
                onRemoved: { removals += 1 }
            )
            .presentationPlacement(.center)
        }
        // Here, not on the sheet: this view outlives the sheet's dismissal, which would cut the haptic off.
        .sensoryFeedback(.warning, trigger: removals)
    }
}

extension NoteSheet {
    /// The exercise's sticky note in the shared editor. Saving trims and caps the text (`StickyNotes.set`; blank clears
    /// it); Remove clears it and calls `onRemoved` first, so the presenter owns the haptic.
    init(
        stickyNoteFor exerciseID: UUID,
        initialText: String,
        in context: ModelContext,
        onRemoved: @escaping () -> Void = {}
    ) {
        self.init(
            initialText: initialText,
            idPrefix: "stickyNote",
            title: "Sticky Note",
            maxLength: StickyNotes.maxLength,
            removeTitle: "Remove Sticky Note",
            onRemove: {
                onRemoved()
                try StickyNotes.clear(exerciseID, in: context)
            },
            onSave: { try StickyNotes.set($0, for: exerciseID, in: context) }
        )
    }
}
