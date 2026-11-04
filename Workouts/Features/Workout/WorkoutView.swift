//
//  WorkoutView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

struct WorkoutView: View {
    /// Opens the Settings sheet, which the root view owns.
    var showSettings: () -> Void = {}
    /// Presents the active workout's cover, which the root view owns.
    var presentWorkout: () -> Void = {}
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    @Environment(SaveErrors.self) private var errors: SaveErrors?
    @Environment(\.modelContext) private var context
    /// The proxy for "the sidebar is showing": the system exposes no environment value for it, and the sidebar-adaptable
    /// `TabView` shows the sidebar only at regular width. Compact (closed Duo, phones) always keeps the folder headers.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: [SortDescriptor(\TemplateFolder.position), SortDescriptor(\TemplateFolder.name)])
    private var folders: [TemplateFolder]
    @Query private var templates: [Template]
    @Query(filter: #Predicate<Workout> { $0.finishedAt != nil }) private var finishedWorkouts: [Workout]

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
    @State private var startFlow = StartWorkoutFlow()
    @Namespace private var cardZoom

    private var showsFolderHeaders: Bool { horizontalSizeClass != .regular }

    /// Compact width presents the preview as a sheet; regular width pushes it so the sidebar stays.
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
                .navigationDestination(item: $previewPush) { template in
                    TemplatePreview(template: template, started: workoutStarted)
                        .navigationTransition(.zoom(sourceID: template.id, in: cardZoom))
                }
                .sheet(
                    item: $previewSheet,
                    onDismiss: {
                        if presentAfterSheet {
                            presentAfterSheet = false
                            presentWorkout()
                        }
                    }
                ) { TemplatePreviewSheet(template: $0, started: workoutStarted) }
                .startWorkoutFlow(startFlow)
                .resumeControl()
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
                            Button("New Folder", systemImage: "folder.badge.plus", action: beginNewFolder)
                                .accessibilityLabel("New Folder")
                                .accessibilityIdentifier("toolbar.add.newFolder")
                        }
                        .accessibilityLabel("Add")
                        .accessibilityIdentifier("toolbar.add")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Settings", systemImage: "gearshape", action: showSettings)
                            .accessibilityLabel("Settings")
                            .accessibilityIdentifier("toolbar.settings")
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
            .accessibilityIdentifier("workout.folderName.confirm")
        }
        .confirmationDialog(
            deleting.map { "Delete \($0.name)?" } ?? "Delete Folder?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { folder in
            deleteActions(for: folder)
        } message: { folder in
            Text(deleteMessage(for: folder))
        }
    }

    @ViewBuilder
    private var content: some View {
        if folders.isEmpty && templates.isEmpty {
            ContentUnavailableView(
                "No Templates",
                systemImage: "dumbbell",
                description: Text("Your workout templates will appear here.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(FolderOperations.ordered(folders)) { folder in
                        FolderSection(
                            folder: folder,
                            name: folder.name,
                            templates: templates(in: folder),
                            finishedWorkouts: finishedWorkouts,
                            namespace: cardZoom,
                            open: open,
                            showsHeader: showsFolderHeaders,
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
                            if showsFolderHeaders {
                                Text("Unfiled (\(unfiled.count))")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityIdentifier("workout.unfiled")
                            }
                            TemplateGrid(
                                templates: unfiled,
                                finishedWorkouts: finishedWorkouts,
                                namespace: cardZoom,
                                open: open
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
            .accessibilityIdentifier("workout.list")
        }
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

    private func startEmpty() {
        startFlow.begin(.empty, engine: engine, errors: errors, present: presentWorkout)
    }
}

#if DEBUG
    #Preview {
        PreviewGallery.host("Workout")
    }
#endif
