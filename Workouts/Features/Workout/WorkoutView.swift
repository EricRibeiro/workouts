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

    /// The folder being renamed, with the alert's text.
    @State private var renaming: TemplateFolder?
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var deleting: TemplateFolder?
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""

    private var showsFolderHeaders: Bool { horizontalSizeClass != .regular }

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
            List {
                ForEach(FolderOperations.ordered(folders)) { folder in
                    FolderSection(
                        folder: folder,
                        name: folder.name,
                        templates: templates(in: folder),
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
                    Section {
                        ForEach(unfiled) { TemplateRow(template: $0) }
                    } header: {
                        if showsFolderHeaders {
                            Text("Unfiled (\(unfiled.count))")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .textCase(nil)
                                .accessibilityIdentifier("workout.unfiled")
                        }
                    }
                }
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

    private func startEmpty() {
        // TODO: with a workout already running, show the "Workout in progress" sheet (Resume / Discard and Start New).
        if let engine, engine.workout == nil {
            do {
                try engine.startEmpty()
            } catch {
                errors?.report(error)
            }
        }
        // Never present the cover without a workout behind it (a failed start would leave a dead end).
        if engine?.workout != nil { presentWorkout() }
    }
}

#if DEBUG
    #Preview {
        PreviewGallery.host("Workout")
    }
#endif
