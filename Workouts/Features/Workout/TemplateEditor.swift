//
//  TemplateEditor.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The template editor (task 3.4), pushed on the Workout tab's stack from the preview's Edit item in both widths: the name
/// (title menu, Rename…), Add Exercise through the multi picker, and the SetTable in template mode. Every edit goes to a
/// `TemplateDraft`; Save writes it to the template in one go, Cancel drops it (asking first when something changed).
/// Regular width puts the table beside, above or across the fold from the exercise pane with an `ArrangementView`, as the
/// logging screen and the past editor do.
///
/// `init(template:)` edits an existing template; `init(newIn:)` edits a new, unsaved one that is created on Save.
struct TemplateEditor: View {
    private let template: Template?
    private let folder: TemplateFolder?

    @Environment(ExerciseStore.self) private var store
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @Environment(SaveErrors.self) private var errors: SaveErrors?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var templates: [Template]

    @State private var draft: TemplateDraft
    /// The draft as it was when the editor opened; dirty means different from this.
    @State private var original: TemplateDraft
    @State private var isDiscardConfirming = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isPickerPresented = false
    @State private var focusedSectionID: UUID?
    /// The block menu's pending prompts (task 3.6); each holds the block's id.
    @State private var isNoteEditing = false
    @State private var noteText = ""
    @State private var noteBlockID: UUID?
    @State private var stickyTarget: StickyTarget?
    @State private var isWarmupAlertShown = false
    @State private var restBlockID: BlockID?
    @State private var removeBlockID: UUID?
    @Query private var stickyNotes: [StickyNote]

    /// A block id as a sheet item.
    private struct BlockID: Identifiable {
        let id: UUID
    }

    private struct StickyTarget: Identifiable {
        let id: UUID
        let exerciseID: UUID
        let text: String
    }

    /// Edits `template`.
    init(template: Template) {
        self.template = template
        folder = template.folder
        let initial = TemplateDraft(template)
        _draft = State(initialValue: initial)
        _original = State(initialValue: initial)
    }

    /// Edits a new template, created in `folder` (nil: unfiled) when saved.
    init(newIn folder: TemplateFolder?) {
        template = nil
        self.folder = folder
        let initial = TemplateDraft()
        _draft = State(initialValue: initial)
        _original = State(initialValue: initial)
    }

    private var isDirty: Bool { draft.hasChanges(from: original) }

    var body: some View {
        let source = TemplateSetTableSource(draft: $draft, store: store)
        let sections = source.sections
        arrangement(source: source, sections: sections)
            .overlay {
                if sections.isEmpty {
                    ContentUnavailableView(
                        "No Exercises Yet",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Add one to start building the template.")
                    )
                    .accessibilityIdentifier("templateEditor.empty")
                }
            }
            .navigationTitle(draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbarTitleMenu {
                Button("Rename…", systemImage: "pencil") {
                    renameText = draft.name
                    isRenaming = true
                }
                .accessibilityIdentifier("templateEditor.titleMenu.rename")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", action: cancel)
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("templateEditor.cancel")
                        // On the button so the regular-width popover points at it.
                        .confirmationDialog(
                            "Discard changes?",
                            isPresented: $isDiscardConfirming,
                            titleVisibility: .visible
                        ) {
                            Button("Discard Changes", role: .destructive) { dismiss() }
                                .accessibilityIdentifier("templateEditor.discard")
                            Button("Keep Editing", role: .cancel) {}
                                .accessibilityIdentifier("templateEditor.keepEditing")
                        } message: {
                            Text("Your changes to this template have not been saved.")
                        }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Exercise", systemImage: "plus") { isPickerPresented = true }
                        .accessibilityLabel("Add Exercise")
                        .accessibilityIdentifier("templateEditor.addExercise")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", action: save)
                        .accessibilityLabel("Save")
                        .accessibilityIdentifier("templateEditor.save")
                }
            }
            .alert("Rename Template", isPresented: $isRenaming) {
                TextField("Name", text: $renameText)
                    .accessibilityIdentifier("templateEditor.rename.field")
                Button("Save") { draft.rename(to: renameText) }
                    .accessibilityIdentifier("templateEditor.rename.save")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("templateEditor.rename.cancel")
            }
            .sheet(isPresented: $isPickerPresented) {
                ExercisePickerView(
                    title: "Add Exercises",
                    mode: .multiple(
                        add: { addExercises($0, asSuperset: false) },
                        superset: { addExercises($0, asSuperset: true) }
                    )
                )
                .presentationPlacement(.center)
            }
            .alert("Note", isPresented: $isNoteEditing) {
                TextField("Note", text: $noteText)
                    .accessibilityIdentifier("templateEditor.note.field")
                Button("Save") {
                    if let noteBlockID { draft.setNote(noteText, for: noteBlockID) }
                }
                .accessibilityIdentifier("templateEditor.note.save")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("templateEditor.note.cancel")
            }
            .alert("Add a working weight first", isPresented: $isWarmupAlertShown) {
                Button("OK", role: .cancel) {}
                    .accessibilityIdentifier("templateEditor.warmup.ok")
            } message: {
                Text("Warm-up sets are built from the first set with a weight.")
            }
            .sheet(item: $stickyTarget) { target in
                StickyNoteEditor(exerciseID: target.exerciseID, initialText: target.text)
                    .presentationPlacement(.center)
            }
            .sheet(item: $restBlockID) { target in
                RestTimerPickerSheet(current: draft.exercises.first { $0.id == target.id }?.restSeconds) {
                    draft.updateRestTimers($0, for: target.id)
                }
                .presentationPlacement(.center)
            }
            .confirmationDialog(
                removeBlockName.map { "Remove \($0)?" } ?? "Remove Exercise?",
                isPresented: Binding(get: { removeBlockID != nil }, set: { if !$0 { removeBlockID = nil } }),
                titleVisibility: .visible
            ) {
                Button("Remove Exercise", role: .destructive) {
                    if let removeBlockID { draft.removeExercise(removeBlockID) }
                    removeBlockID = nil
                }
                .accessibilityIdentifier("templateEditor.remove.confirm")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("templateEditor.remove.cancel")
            } message: {
                Text("Its sets are removed from the template. Nothing is saved until you tap Save.")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.templateEditor")
    }

    private var removeBlockName: String? {
        draft.exercises.first { $0.id == removeBlockID }?.name
    }

    // MARK: Block menu

    private var blockActions: SetTableBlockActions {
        SetTableBlockActions(
            note: { id in
                noteBlockID = id
                noteText = draft.exercises.first { $0.id == id }?.note ?? ""
                isNoteEditing = true
            },
            stickyNote: { id in
                guard let block = draft.exercises.first(where: { $0.id == id }) else { return }
                let text = stickyNotes.first { $0.exerciseID == block.exerciseID }?.text ?? ""
                stickyTarget = StickyTarget(id: id, exerciseID: block.exerciseID, text: text)
            },
            addWarmups: { id in
                if draft.addWarmupSets(to: id) == 0 { isWarmupAlertShown = true }
            },
            updateRest: { id in restBlockID = BlockID(id: id) },
            remove: { id in removeBlockID = id }
        )
    }

    // MARK: Table

    /// One ArrangementView in both widths so folding never swaps the table's identity (draft, focus and scroll stay); the
    /// pane is simply absent, and the split disabled, on compact width (as in the logging screen).
    private func arrangement(source: any SetTableDataSource, sections: [SetTableSection]) -> some View {
        ArrangementView {
            SetTable(source: source, focusedSection: $focusedSectionID, blockActions: blockActions)
        } secondary: {
            if horizontalSizeClass == .regular {
                let focused = focusedSection(in: sections)
                ExercisePane(exerciseName: focused?.name, exerciseID: focused?.exerciseID)
            }
        }
        .arrangementViewStyle(
            .split.axes(horizontalSizeClass == .regular ? Axis.Set([.horizontal, .vertical]) : Axis.Set())
        )
    }

    /// The block the pane shows: the last focused one while it still exists, else the first.
    private func focusedSection(in sections: [SetTableSection]) -> SetTableSection? {
        sections.first { $0.id == focusedSectionID } ?? sections.first
    }

    // MARK: Actions

    private func addExercises(_ infos: [ExerciseInfo], asSuperset: Bool) {
        draft.addExercises(
            infos,
            defaultUnit: settings?.defaultUnit ?? SettingsStore.defaultUnitDefault,
            defaultRestSeconds: settings?.defaultRestSeconds ?? SettingsStore.defaultRestSecondsDefault,
            asSuperset: asSuperset
        )
    }

    private func cancel() {
        if isDirty {
            isDiscardConfirming = true
        } else {
            dismiss()
        }
    }

    private func save() {
        do {
            if let template {
                // Unchanged and not new: just closes.
                if isDirty { try draft.save(to: template, in: context) }
            } else {
                try draft.insertNew(in: folder, context: context, siblings: templates)
            }
            dismiss()
        } catch {
            // The draft stays as it is, so Save can be tried again.
            errors?.report(error)
        }
    }
}

// MARK: - Gallery and previews

#if DEBUG
    /// The editor of the first sample template, for the gallery (`-preview TemplateEditor`) and the previews.
    struct TemplateEditorDemo: View {
        @Query(sort: [SortDescriptor(\Template.position), SortDescriptor(\Template.name)]) private var templates:
            [Template]
        @State private var settings = SettingsStore()
        @State private var errors = SaveErrors()

        var body: some View {
            NavigationStack {
                if let first = templates.first {
                    TemplateEditor(template: first)
                } else {
                    ProgressView()
                }
            }
            .environment(settings)
            .environment(errors)
            .saveErrorAlert()
        }
    }

    #Preview("Large") {
        PreviewGallery.host("TemplateEditor")
            .dynamicTypeSize(.large)
    }

    #Preview("Accessibility 3") {
        PreviewGallery.host("TemplateEditor")
            .dynamicTypeSize(.accessibility3)
    }
#endif
