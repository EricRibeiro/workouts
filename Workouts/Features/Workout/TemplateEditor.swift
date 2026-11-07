//
//  TemplateEditor.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The template editor (task 3.4), presented as a full-screen cover (modal: a self-contained edit with Save and Cancel, so a
/// tab reselect cannot pop it and lose the edits) over the Workout tab from the preview's Edit item or New Template, in a
/// `NavigationStack` of its own: the name
/// (title menu: Rename…, Edit Note…), Add Exercise through the multi picker, and the SetTable in template mode. Every edit goes to a
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
    @State private var isNoteEditing = false
    @State private var isPickerPresented = false
    @State private var focusedSectionID: UUID?
    /// The block menu's pending prompts (task 3.6).
    @State private var blockSheets = BlockActionState()

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
            .navigationTitle(draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                Button("Rename…", systemImage: "pencil") {
                    renameText = draft.name
                    isRenaming = true
                }
                .accessibilityIdentifier("templateEditor.titleMenu.rename")
                Button("Edit Note…", systemImage: "note.text") { isNoteEditing = true }
                    .accessibilityIdentifier("templateEditor.titleMenu.note")
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
            .sheet(isPresented: $isNoteEditing) {
                NoteSheet(initialText: draft.note, idPrefix: "templateEditor.templateNote") { draft.setNote($0) }
                    .presentationPlacement(.center)
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
            .blockActionSheets(blockSheets, host: blockHost)
            // Fires when "Discard changes?" is raised, not when Discard is tapped: confirming dismisses this screen in the
            // same pass, which would cut the haptic off, and the presenters (several) cannot be hooked cheaply.
            .sensoryFeedback(.warning, trigger: isDiscardConfirming) { _, shown in shown }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.templateEditor")
    }

    // MARK: Block menu

    private var blockActions: SetTableBlockActions { blockSheets.actions(host: blockHost) }

    /// The draft behind the block menu's prompts.
    private var blockHost: BlockActionHost {
        BlockActionHost(
            blocks: draft.exercises.map {
                BlockActionBlock(
                    id: $0.id,
                    exerciseID: $0.exerciseID,
                    name: $0.name,
                    note: $0.note,
                    restSeconds: $0.restSeconds,
                    supersetGroup: $0.supersetGroup,
                    unit: $0.unit,
                    barType: $0.barType,
                    barWeight: $0.barWeight
                )
            },
            idPrefix: "templateEditor",
            removeMessage: "Its sets are removed from the template. Nothing is saved until you tap Save.",
            setNote: { draft.setNote($1, for: $0) },
            addWarmups: { draft.addWarmupSets(to: $0) },
            setRest: { draft.updateRestTimers($1, for: $0) },
            remove: { draft.removeExercise($0) },
            replace: { id, info in
                draft.replaceExercise(
                    id,
                    with: info,
                    defaultUnit: settings?.defaultUnit ?? SettingsStore.defaultUnitDefault
                )
            },
            makeSuperset: { id, picked in draft.makeSuperset([id] + picked) },
            removeFromSuperset: { draft.removeFromSuperset($0) },
            savePreferences: { id, values in
                draft.setUnit(values.unit, for: id)
                draft.setBar(values.barType, weight: values.barWeight, for: id)
            }
        )
    }

    // MARK: Table

    /// One ArrangementView in both widths so folding never swaps the table's identity (draft, focus and scroll stay); the
    /// pane is simply absent, and the split disabled, on compact width (as in the logging screen) and while the template has
    /// no exercise, so the empty state (inside the primary region) has the whole width to itself instead of sharing it
    /// with a pane that has nothing to show.
    private func arrangement(source: any SetTableDataSource, sections: [SetTableSection]) -> some View {
        let showsPane = horizontalSizeClass == .regular && !sections.isEmpty
        return ArrangementView {
            VStack(spacing: 0) {
                noteLine
                SetTable(source: source, focusedSection: $focusedSectionID, blockActions: blockActions)
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
            }
        } secondary: {
            if showsPane {
                let focused = focusedSection(in: sections)
                ExercisePane(exerciseName: focused?.name, exerciseID: focused?.exerciseID)
            }
        }
        // The system split's placement in every pose but the half-open laptop one, where the table drops to the lower half
        // (6.1); one view tree throughout, so no pose change recreates the table.
        .arrangementViewStyle(
            BenchArrangementStyle(axes: showsPane ? Axis.Set([.horizontal, .vertical]) : Axis.Set())
        )
    }

    /// The template's note as a secondary line above the first block (as `TemplatePreview` shows it); tapping it opens the
    /// same Edit Note sheet as the title menu. Absent while the note is empty.
    @ViewBuilder
    private var noteLine: some View {
        if !draft.note.isEmpty {
            Button {
                isNoteEditing = true
            } label: {
                Text(draft.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Template note: \(draft.note)")
            .accessibilityHint("Edits the note")
            .accessibilityIdentifier("templateEditor.note")
        }
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

// MARK: - Presenting

/// What the Workout tab's editor cover edits: an existing template, or a new one.
enum TemplateEditorTarget: Identifiable {
    case existing(Template)
    case new

    var id: String {
        switch self {
        case .existing(let template): template.id.uuidString
        case .new: "new"
        }
    }
}

extension View {
    /// Presents the template editor for `target` as a full-screen cover with its own `NavigationStack`; a new template
    /// goes into `folder` (nil: unfiled).
    func templateEditorCover(_ target: Binding<TemplateEditorTarget?>, newIn folder: TemplateFolder?) -> some View {
        fullScreenCover(item: target) { item in
            NavigationStack {
                switch item {
                case .existing(let template): TemplateEditor(template: template)
                case .new: TemplateEditor(newIn: folder)
                }
            }
            .editorCoverHost()
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
