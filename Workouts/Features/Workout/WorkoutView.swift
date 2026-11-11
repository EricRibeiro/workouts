//
//  WorkoutView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

struct WorkoutView: View {
    /// Presents the active workout's cover, which the root view owns.
    var presentWorkout: () -> Void = {}
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    @Environment(SaveErrors.self) private var errors: SaveErrors?
    @Environment(\.modelContext) private var context
    /// Regular width opens the preview with a push; compact presents a sheet.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: [SortDescriptor(\TemplateFolder.position), SortDescriptor(\TemplateFolder.name)])
    private var folders: [TemplateFolder]
    @Query private var templates: [Template]
    /// The newest edit among finished workouts: with the store generation it keys "last performed", which is built from one
    /// fetch of the finished workouts per change in the task, not from an observed query of all of them.
    @Query(Workout.newestFinishedEdit) private var newestFinished: [Workout]
    @Environment(StoreGeneration.self) private var generation: StoreGeneration?
    /// "Last performed" for every card, built once per change of the finished workouts (not once per card per body).
    @State private var lastPerformed = TemplateCardSummary.LastPerformedIndex()

    /// The folder being renamed, with the alert's text.
    @State private var renaming: TemplateFolder?
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var deleting: TemplateFolder?
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    /// The card that opened the preview: a sheet at compact width, a zoom push at regular width.
    @State private var previewSheet: Template?
    @State private var previewPush: Template?
    /// A workout was started from the sheet: the cover opens once the sheet has gone (a sheet and a cover cannot overlap).
    @State private var presentAfterSheet = false
    /// The editor cover (task 3.4): an existing template from the preview's Edit item, or a new one from the Add menu.
    @State private var editing: TemplateEditorTarget?
    /// The card whose Delete was chosen, until the confirmation answers.
    @State private var deletingTemplate: Template?
    /// Bumps when a folder or template is deleted; drives the `.warning` haptic.
    @State private var destructiveCount = 0
    /// Edit was tapped in the sheet: the editor cover opens once the sheet has gone (a sheet and a cover cannot overlap).
    @State private var editAfterSheet: Template?
    @State private var startFlow = StartWorkoutFlow()
    @Namespace private var cardZoom

    /// Compact width presents the preview as a sheet; regular width pushes it.
    private func open(_ template: Template) {
        if horizontalSizeClass == .regular {
            previewPush = template
        } else {
            previewSheet = template
        }
    }

    private func templates(in folder: TemplateFolder) -> [Template] {
        FolderOperations.orderedTemplates(templates.filter { $0.folder?.id == folder.id })
    }

    private var unfiled: [Template] {
        FolderOperations.orderedTemplates(templates.filter { $0.folder == nil })
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Workout")
                // The title stays large in the bar row: with the default large title, folding the Duo open with the grid
                // scrolled left it collapsed to a small inline one that History (fresh launch) did not show.
                .toolbarTitleDisplayMode(.inlineLarge)
                .navigationDestination(item: $previewPush) { template in
                    TemplatePreview(template: template, started: workoutStarted, edit: edit)
                        .navigationTransition(.zoom(sourceID: template.id, in: cardZoom))
                }
                .templateEditorCover($editing, newIn: FolderOperations.ordered(folders).first)
                #if DEBUG
                    // `-openNewTemplate` / `-editFirstTemplate`: open the empty new-template editor or the first template's
                    // editor at launch (screenshots, where nothing can tap).
                    .task {
                        let arguments = ProcessInfo.processInfo.arguments
                        if arguments.contains("-openNewTemplate") { editing = .new }
                        if arguments.contains("-editFirstTemplate"), let first = templates.first {
                            editing = .existing(first)
                        }
                    }
                #endif
                .sheet(
                    item: $previewSheet,
                    onDismiss: {
                        if presentAfterSheet {
                            presentAfterSheet = false
                            presentWorkout()
                        }
                        if let template = editAfterSheet {
                            editAfterSheet = nil
                            editing = .existing(template)
                        }
                    }
                ) { TemplatePreviewSheet(template: $0, started: workoutStarted, edit: edit) }
                .resumeControl()
                .settingsControl()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Add", systemImage: "plus") {
                            Button(
                                "Empty Workout",
                                systemImage: "figure.strengthtraining.traditional",
                                action: startEmpty
                            )
                            .accessibilityLabel("Empty Workout")
                            .accessibilityIdentifier("toolbar.add.emptyWorkout")
                            Button("New Template", systemImage: "square.and.pencil") {
                                editing = .new
                            }
                            .accessibilityLabel("New Template")
                            .accessibilityIdentifier("workout.newTemplate")
                            Button("New Folder", systemImage: "folder.badge.plus", action: beginNewFolder)
                                .accessibilityLabel("New Folder")
                                .accessibilityIdentifier("toolbar.add.newFolder")
                        }
                        .accessibilityLabel("Add")
                        .accessibilityIdentifier("toolbar.add")
                        .startWorkoutFlow(startFlow)
                    }
                }
        }
        .accessibilityIdentifier("screen.workout")
        .alert("New Folder", isPresented: $isCreatingFolder) {
            TextField("Name", text: $newFolderName)
                .accessibilityIdentifier("workout.folderName")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("workout.folderName.cancel")
            Button("Create") {
                perform { try FolderOperations.create(named: newFolderName, in: context) }
            }
            .disabled(FolderOperations.cleanedName(newFolderName) == nil)
            .accessibilityIdentifier("workout.folderName.confirm")
        }
        .alert("Rename Folder", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
                .accessibilityIdentifier("workout.folderName")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("workout.folderName.cancel")
            Button("Rename") {
                // `renaming` outlives the alert on purpose: the system flips `isRenaming` before this action runs.
                if let folder = renaming {
                    perform { try FolderOperations.rename(folder, to: renameText, in: context) }
                }
            }
            .disabled(FolderOperations.cleanedName(renameText) == nil)
            .accessibilityIdentifier("workout.folderName.confirm")
        }
        // Alerts, not dialogs: both are raised from context menus, which are gone by then, so a popover's arrow would
        // have nothing to point at.
        .alert(
            deleting.map { "Delete \($0.name)?" } ?? "Delete Folder?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { folder in
            deleteActions(for: folder)
        } message: { folder in
            Text(deleteMessage(for: folder))
        }
        .alert(
            deletingTemplate.map { "Delete \($0.name)?" } ?? "Delete Template?",
            isPresented: Binding(get: { deletingTemplate != nil }, set: { if !$0 { deletingTemplate = nil } }),
            presenting: deletingTemplate
        ) { template in
            Button("Delete Template", role: .destructive) { delete(template) }
                .accessibilityIdentifier("templateCard.delete.confirm")
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The template is deleted. Workouts you did from it stay in your history.")
        }
        .sensoryFeedback(.warning, trigger: destructiveCount)
    }

    @ViewBuilder
    private var content: some View {
        if folders.isEmpty && templates.isEmpty {
            ContentUnavailableView {
                Label("No Templates Yet", systemImage: "dumbbell")
            } description: {
                Text("Tap New Template to plan your first workout.")
            } actions: {
                Button("New Template", systemImage: "square.and.pencil") { editing = .new }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Color.onAccent)
                    .accessibilityLabel("New Template")
                    .accessibilityIdentifier("workout.empty.newTemplate")
            }
        } else {
            ScrollView {
                FoldFlow {
                    ForEach(FolderOperations.ordered(folders)) { folder in
                        FolderSection(
                            folder: folder,
                            name: folder.name,
                            templates: templates(in: folder),
                            lastPerformed: lastPerformed,
                            namespace: cardZoom,
                            open: open,
                            actions: cardActions,
                            canMoveUp: FolderOperations.canMove(folder, .up, in: folders),
                            canMoveDown: FolderOperations.canMove(folder, .down, in: folders),
                            rename: {
                                renameText = folder.name
                                renaming = folder
                                isRenaming = true
                            },
                            move: { direction in move(folder, direction) },
                            delete: { deleting = folder }
                        )
                    }
                    if !unfiled.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Unfiled (\(unfiled.count))")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(minHeight: 44)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("workout.unfiled")
                            TemplateGrid(
                                templates: unfiled,
                                lastPerformed: lastPerformed,
                                namespace: cardZoom,
                                open: open,
                                actions: cardActions
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
            .accessibilityIdentifier("workout.list")
            .task(
                id: FinishedWorkoutsStamp(
                    newestEdit: newestFinished.first?.updatedAt,
                    generation: generation?.value ?? 0
                )
            ) {
                // The reader's context reads the store: flush edits the main context has not saved yet.
                context.saveIfChanged(reportingTo: errors)
                let index = try? await WorkoutStatsReader.loadLastPerformedIndex(in: context.container)
                guard !Task.isCancelled, let index else { return }
                lastPerformed = index
            }
        }
    }

    // MARK: Card actions

    private var cardActions: TemplateCardActions {
        TemplateCardActions(
            folders: FolderOperations.ordered(folders),
            edit: edit,
            duplicate: { template in perform { try FolderOperations.duplicate(template, in: context) } },
            move: { template, folder in perform { try FolderOperations.move(template, to: folder, in: context) } },
            delete: { deletingTemplate = $0 },
            start: { template in
                startFlow.begin(.template(template), engine: engine, errors: errors, present: workoutStarted)
            }
        )
    }

    private func delete(_ template: Template) {
        destructiveCount += 1
        perform { try FolderOperations.delete(template, in: context) }
    }

    // MARK: Folder dialogs

    @ViewBuilder
    private func deleteActions(for folder: TemplateFolder) -> some View {
        let count = templates(in: folder).count
        if count > 0 {
            Button("Move \(count == 1 ? "1 Template" : "\(count) Templates") to Unfiled") {
                delete(folder, .moveTemplatesToUnfiled)
            }
            .accessibilityIdentifier("workout.folder.delete.move")
        }
        Button(deleteTitle(count: count), role: .destructive) {
            delete(folder, .deleteTemplates)
        }
        .accessibilityIdentifier("workout.folder.delete.confirm")
        Button("Cancel", role: .cancel) {}
    }

    private func deleteTitle(count: Int) -> String {
        switch count {
        case 0: "Delete Folder"
        case 1: "Delete Folder and 1 Template"
        default: "Delete Folder and \(count) Templates"
        }
    }

    private func deleteMessage(for folder: TemplateFolder) -> String {
        let count = templates(in: folder).count
        guard count > 0 else { return "The folder is empty." }
        let noun = count == 1 ? "template" : "templates"
        let pronoun = count == 1 ? "it" : "them"
        return
            "\(folder.name) has \(count) \(noun). Move \(pronoun) to Unfiled, or delete \(pronoun) with the folder. "
            + "Workouts you did from \(pronoun) stay in your history."
    }

    private func beginNewFolder() {
        newFolderName = ""
        isCreatingFolder = true
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            errors?.report(error)
        }
    }

    private func move(_ folder: TemplateFolder, _ direction: FolderMove) {
        perform { try FolderOperations.move(folder, direction, among: folders, in: context) }
    }

    private func delete(_ folder: TemplateFolder, _ deletion: FolderDeletion) {
        if deletion == .deleteTemplates { destructiveCount += 1 }
        let key = FolderSection.collapsedKey(for: folder.id)
        perform {
            try FolderOperations.delete(folder, deletion, in: context)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// A workout is running and should be on screen: close the preview (the sheet first, then the cover), or pop the push.
    private func workoutStarted() {
        if previewSheet != nil {
            presentAfterSheet = true
            previewSheet = nil
        } else {
            previewPush = nil
            presentWorkout()
        }
    }

    /// Edit from the preview: the sheet closes first (then the editor cover opens); a pushed preview stays under the
    /// cover, so Save and Cancel return to it.
    private func edit(_ template: Template) {
        if previewSheet != nil {
            editAfterSheet = template
            previewSheet = nil
        } else {
            editing = .existing(template)
        }
    }

    private func startEmpty() {
        startFlow.begin(.empty, engine: engine, errors: errors, present: presentWorkout)
    }
}

#if DEBUG
    #Preview {
        PreviewGallery.host("Workout")
    }
#endif
