import Foundation
import SwiftData
import os

/// Sticky notes by exercise id (task 4.5): one per exercise, enforced here because CloudKit forbids unique constraints.
public nonisolated enum StickyNotes {
    /// The longest note, in characters (the web app's limit).
    public static let maxLength = 2000

    /// The note's text for `exerciseID`; nil when there is none (an empty note counts as none) or the store cannot be
    /// read (logged).
    @MainActor public static func text(for exerciseID: UUID, in context: ModelContext) -> String? {
        do {
            guard let note = try notes(for: exerciseID, in: context).first, !note.text.isEmpty else { return nil }
            return note.text
        } catch {
            KitLog.library.error(
                "Could not read the sticky note: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Saves `text` (trimmed, capped at `maxLength`) as the exercise's note. Blank text clears it. Duplicates left by a
    /// CloudKit merge collapse into one row.
    @MainActor public static func set(_ text: String, for exerciseID: UUID, in context: ModelContext) throws {
        try set(text, for: exerciseID, in: context, saveHook: nil)
    }

    /// ``set(_:for:in:)`` with a test seam: `saveHook` runs just before the save, so a test can fail it.
    @MainActor static func set(
        _ text: String,
        for exerciseID: UUID,
        in context: ModelContext,
        saveHook: (() throws -> Void)?
    ) throws {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        guard !trimmed.isEmpty else { return try clear(exerciseID, in: context, saveHook: saveHook) }
        let existing = try notes(for: exerciseID, in: context)
        if let keep = existing.first {
            keep.text = trimmed
            keep.updatedAt = Date()
            for extra in existing.dropFirst() { context.delete(extra) }
        } else {
            context.insert(StickyNote(exerciseID: exerciseID, text: trimmed))
        }
        try save(context, saveHook)
    }

    /// Deletes the exercise's note, if any.
    @MainActor public static func clear(_ exerciseID: UUID, in context: ModelContext) throws {
        try clear(exerciseID, in: context, saveHook: nil)
    }

    /// ``clear(_:in:)`` with the same test seam as ``set(_:for:in:saveHook:)``.
    @MainActor static func clear(
        _ exerciseID: UUID,
        in context: ModelContext,
        saveHook: (() throws -> Void)?
    ) throws {
        let existing = try notes(for: exerciseID, in: context)
        guard !existing.isEmpty else { return }
        for note in existing { context.delete(note) }
        try save(context, saveHook)
    }

    /// Saves, and on failure rolls the context back so the change is not committed by the next unrelated save.
    @MainActor private static func save(_ context: ModelContext, _ saveHook: (() throws -> Void)?) throws {
        do {
            try saveHook?()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Throws rather than reading a failed fetch as "no note", which would make `set` insert a duplicate.
    @MainActor private static func notes(for exerciseID: UUID, in context: ModelContext) throws -> [StickyNote] {
        let descriptor = FetchDescriptor<StickyNote>(
            predicate: #Predicate { $0.exerciseID == exerciseID },
            sortBy: [SortDescriptor(\.updatedAt)]
        )
        return try context.fetch(descriptor)
    }
}
