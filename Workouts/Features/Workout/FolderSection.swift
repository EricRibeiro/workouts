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
    let lastPerformed: TemplateCardSummary.LastPerformedIndex
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
        lastPerformed: TemplateCardSummary.LastPerformedIndex,
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
        self.lastPerformed = lastPerformed
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
                    lastPerformed: lastPerformed,
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

    /// Regular width lays the folders in two columns, so a move goes sideways: earlier or later in the order.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var sideBySide: Bool { horizontalSizeClass == .regular }
    private var earlierTitle: LocalizedStringKey { sideBySide ? "Move Earlier" : "Move Up" }
    private var laterTitle: LocalizedStringKey { sideBySide ? "Move Later" : "Move Down" }
    private var earlierSymbol: String { sideBySide ? "arrow.left" : "arrow.up" }
    private var laterSymbol: String { sideBySide ? "arrow.right" : "arrow.down" }

    var body: some View {
        menu
            .frame(maxWidth: .infinity, alignment: .leading)
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
                Button(earlierTitle, systemImage: earlierSymbol) { move(.up) }
                    .accessibilityIdentifier("workout.folder.moveUp")
            }
            if canMoveDown {
                Button(laterTitle, systemImage: laterSymbol) { move(.down) }
                    .accessibilityIdentifier("workout.folder.moveDown")
            }
            Button("Delete Folder", systemImage: "trash", role: .destructive, action: delete)
                .accessibilityIdentifier("workout.folder.delete")
        } label: {
            HStack(spacing: 6) {
                Text("\(name) (\(count))")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
            }
            // The title and chevron toggle the folder: give them the HIG's 44 pt minimum hit target. The row hugs its
            // content (the frame that pushes it to the leading edge sits outside the Menu), so the empty trailing space is
            // not tappable and the hit area never spans the hinge on the open Duo.
            .frame(minHeight: 44)
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
        // The menu opens on a long press, which VoiceOver cannot do: the same actions, under the same conditions.
        .accessibilityActions {
            Button("Rename Folder", action: rename)
            if canMoveUp { Button(earlierTitle) { move(.up) } }
            if canMoveDown { Button(laterTitle) { move(.down) } }
            Button("Delete Folder", action: delete)
        }
        .accessibilityIdentifier("workout.folder.\(id.uuidString).toggle")
    }
}
