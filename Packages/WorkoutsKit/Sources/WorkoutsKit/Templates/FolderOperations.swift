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

    // MARK: Templates

    /// The templates in `folder` (nil: unfiled), ordered, read from the store so it holds before the relationship
    /// arrays have refreshed.
    private static func siblings(in folder: TemplateFolder?, context: ModelContext) throws -> [Template] {
        let all = try context.fetch(FetchDescriptor<Template>())
        return orderedTemplates(all.filter { $0.folder?.id == folder?.id })
    }

    /// Copies the template, its exercises and their sets (all with new ids) into the same folder, named "<name> copy",
    /// right after the original; the siblings behind it are renumbered 0, 1, 2. Returns the copy.
    @discardableResult
    public static func duplicate(_ template: Template, in context: ModelContext) throws -> Template {
        let now = Date()
        let copy = Template(name: "\(template.name) copy", note: template.note, folder: template.folder)
        copy.createdAt = now
        copy.updatedAt = now
        context.insert(copy)
        for exercise in (template.exercises ?? []).sorted(by: { $0.position < $1.position }) {
            let row = TemplateExercise(
                exerciseID: exercise.exerciseID,
                exerciseName: exercise.exerciseName,
                position: exercise.position,
                supersetGroup: exercise.supersetGroup,
                note: exercise.note,
                restSeconds: exercise.restSeconds,
                unit: exercise.unit,
                barType: exercise.barType,
                barWeight: exercise.barWeight,
                updatedAt: now
            )
            row.template = copy
            context.insert(row)
            for set in (exercise.sets ?? []).sorted(by: { $0.position < $1.position }) {
                let planned = TemplateSet(
                    position: set.position,
                    kind: set.kind,
                    weight: set.weight,
                    reps: set.reps,
                    durationSeconds: set.durationSeconds,
                    distanceMeters: set.distanceMeters
                )
                planned.templateExercise = row
                context.insert(planned)
            }
        }
        var list = try siblings(in: template.folder, context: context).filter { $0.id != copy.id }
        let index = list.firstIndex(where: { $0.id == template.id }).map { $0 + 1 } ?? list.count
        list.insert(copy, at: index)
        for (position, item) in list.enumerated() where item.position != position {
            item.position = position
            if item.id != copy.id { item.updatedAt = now }
        }
        try save(context)
        return copy
    }

    /// Moves the template to the end of `folder` (nil: unfiled). Returns `false` (and changes nothing) when it is
    /// already there.
    @discardableResult
    public static func move(_ template: Template, to folder: TemplateFolder?, in context: ModelContext) throws -> Bool {
        guard template.folder?.id != folder?.id else { return false }
        let others = try siblings(in: folder, context: context)
        template.folder = folder
        template.position = (others.map(\.position).max() ?? -1) + 1
        template.updatedAt = Date()
        try save(context)
        return true
    }

    /// Deletes the template with its exercises and sets. Workouts done from it stay in history (their link clears).
    public static func delete(_ template: Template, in context: ModelContext) throws {
        context.delete(template)
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
