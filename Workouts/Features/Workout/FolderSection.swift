//
//  FolderSection.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// One folder on the Workout tab: a header over a grid of its template cards (tasks 3.1, 3.2a).
///
/// The collapsed flag is per-device `@AppStorage`, keyed by the folder id (never synced). It drives only the header, which
/// always shows (also beside an expanded sidebar, which lists the folders too).
struct FolderSection: View {
    let folder: TemplateFolder
    /// `folder.name`, read by the list's body so a rename re-renders the header (see `FolderHeader`).
    let name: String
    let templates: [Template]
    let finishedWorkouts: [Workout]
    let namespace: Namespace.ID
    let open: (Template) -> Void
    let actions: TemplateCardActions
    let canMoveUp: Bool
    let canMoveDown: Bool
    let rename: () -> Void
    let move: (FolderMove) -> Void
    let delete: () -> Void

    @AppStorage private var collapsed: Bool

    init(
        folder: TemplateFolder,
        name: String,
        templates: [Template],
        finishedWorkouts: [Workout],
        namespace: Namespace.ID,
        open: @escaping (Template) -> Void,
        actions: TemplateCardActions,
        canMoveUp: Bool,
        canMoveDown: Bool,
        rename: @escaping () -> Void,
        move: @escaping (FolderMove) -> Void,
        delete: @escaping () -> Void
    ) {
        self.folder = folder
        self.name = name
        self.templates = templates
        self.finishedWorkouts = finishedWorkouts
        self.namespace = namespace
        self.open = open
        self.actions = actions
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.rename = rename
        self.move = move
        self.delete = delete
        _collapsed = AppStorage(wrappedValue: false, FolderSection.collapsedKey(for: folder.id))
    }

    /// The `UserDefaults` key of a folder's collapsed flag.
    static func collapsedKey(for id: UUID) -> String { "workoutFolderCollapsed.\(id.uuidString)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FolderHeader(
                id: folder.id,
                name: name,
                count: templates.count,
                collapsed: $collapsed,
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                rename: rename,
                move: move,
                delete: delete
            )
            if !collapsed, !templates.isEmpty {
                TemplateGrid(
                    templates: templates,
                    finishedWorkouts: finishedWorkouts,
                    namespace: namespace,
                    open: open,
                    actions: actions
                )
            }
        }
    }
}

/// A folder's section header. It takes plain values, not the model: a header that read `folder.name` itself stayed stale
/// after a rename (the list's header sits outside the observation that re-renders the section), so the list's body
/// reads the name and passes it down.
private struct FolderHeader: View {
    let id: UUID
    let name: String
    let count: Int
    @Binding var collapsed: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let rename: () -> Void
    let move: (FolderMove) -> Void
    let delete: () -> Void

    var body: some View {
        menu
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workout.folder.\(id.uuidString)")
    }

    /// A `Menu` with a primary action: a tap toggles, a long press opens the folder's actions. (A `contextMenu` on a
    /// `Section` header never opened, and a `Button` there swallowed the long press, in the Duo simulator.)
    private var menu: some View {
        Menu {
            Button("Rename Folder", systemImage: "pencil", action: rename)
                .accessibilityIdentifier("workout.folder.rename")
            if canMoveUp {
                Button("Move Up", systemImage: "arrow.up") { move(.up) }
                    .accessibilityIdentifier("workout.folder.moveUp")
            }
            if canMoveDown {
                Button("Move Down", systemImage: "arrow.down") { move(.down) }
                    .accessibilityIdentifier("workout.folder.moveDown")
            }
            Button("Delete Folder", systemImage: "trash", role: .destructive, action: delete)
                .accessibilityIdentifier("workout.folder.delete")
        } label: {
            HStack {
                Text("\(name) (\(count))")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
            }
            .contentShape(Rectangle())
        } primaryAction: {
            withAnimation { collapsed.toggle() }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .textCase(nil)
        .accessibilityLabel("\(name), \(count) \(count == 1 ? "template" : "templates")")
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("workout.folder.\(id.uuidString).toggle")
    }
}
