import Foundation
import SwiftData

/// What happens to a folder's templates when the folder is deleted.
public enum FolderDeletion: Sendable, Equatable {
    /// The templates survive, unfiled, after the existing unfiled ones (order kept).
    case moveTemplatesToUnfiled
    /// The templates go with the folder (the model's cascade). Workouts done from them stay in history.
    case deleteTemplates
}

/// Which way a folder moves in the list.
public enum FolderMove: Sendable, Equatable {
    case up
    case down
}

/// Pure folder rules over the models: ordering, creating, renaming, reordering and deleting. Each mutating function
/// saves; on a failed save it rolls the context back and rethrows, so the screen keeps matching the store.
public enum FolderOperations {
    /// The web's cap on a folder name (`SWP:271`).
    public static let maxNameLength = 120

    /// Folders by position, then name, then id (ties and gaps are tolerated).
    public static func ordered(_ folders: [TemplateFolder]) -> [TemplateFolder] {
        folders.sorted { lhs, rhs in
            if lhs.position != rhs.position { return lhs.position < rhs.position }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Templates by position, then name, then id.
    public static func orderedTemplates(_ templates: [Template]) -> [Template] {
        templates.sorted { lhs, rhs in
            if lhs.position != rhs.position { return lhs.position < rhs.position }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Trimmed and clamped to `maxNameLength`; `nil` when nothing is left.
    public static func cleanedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }

    /// Creates a folder after the last one. Returns `nil` (and creates nothing) for a blank name.
    @discardableResult
    public static func create(named raw: String, in context: ModelContext) throws -> TemplateFolder? {
        guard let name = cleanedName(raw) else { return nil }
        let existing = try context.fetch(FetchDescriptor<TemplateFolder>())
        let folder = TemplateFolder(name: name, position: (existing.map(\.position).max() ?? -1) + 1)
        context.insert(folder)
        try save(context)
        return folder
    }

    /// Renames the folder. Returns `false` (and changes nothing) for a blank name.
    @discardableResult
    public static func rename(_ folder: TemplateFolder, to raw: String, in context: ModelContext) throws -> Bool {
        guard let name = cleanedName(raw) else { return false }
        guard folder.name != name else { return true }
        folder.name = name
        folder.updatedAt = Date()
        try save(context)
        return true
    }

    /// Whether the folder can move that way in `folders` (not first for up, not last for down).
    public static func canMove(_ folder: TemplateFolder, _ move: FolderMove, in folders: [TemplateFolder]) -> Bool {
        let list = ordered(folders)
        guard let index = list.firstIndex(where: { $0.id == folder.id }) else { return false }
        return move == .up ? index > 0 : index < list.count - 1
    }

    /// Swaps the folder with its neighbour and renumbers every position 0, 1, 2 so ties and gaps disappear.
    /// Returns `false` when it is already at that end.
    @discardableResult
    public static func move(
        _ folder: TemplateFolder,
        _ move: FolderMove,
        among folders: [TemplateFolder],
        in context: ModelContext
    ) throws -> Bool {
        var list = ordered(folders)
        guard let index = list.firstIndex(where: { $0.id == folder.id }) else { return false }
        let target = move == .up ? index - 1 : index + 1
        guard list.indices.contains(target) else { return false }
        list.swapAt(index, target)
        let now = Date()
        for (position, item) in list.enumerated() where item.position != position {
            item.position = position
            item.updatedAt = now
        }
        try save(context)
        return true
    }

    /// Deletes the folder. With `.moveTemplatesToUnfiled` its templates are unfiled first, placed after the templates
    /// that already have no folder, in their own order.
    public static func delete(_ folder: TemplateFolder, _ deletion: FolderDeletion, in context: ModelContext) throws {
        if deletion == .moveTemplatesToUnfiled {
            let all = try context.fetch(FetchDescriptor<Template>())
            var next = (all.filter { $0.folder == nil }.map(\.position).max() ?? -1) + 1
            let now = Date()
            for template in orderedTemplates(folder.templates ?? []) {
                template.folder = nil
                template.position = next
                template.updatedAt = now
                next += 1
            }
        }
        context.delete(folder)
        try save(context)
    }

    private static func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
