import Foundation
import SwiftData

/// Sticky notes by exercise id (task 4.5): one per exercise, enforced here because CloudKit forbids unique constraints.
public nonisolated enum StickyNotes {
    /// The longest note, in characters (the web app's limit).
    public static let maxLength = 2000

    /// The note's text for `exerciseID`; nil when there is none (an empty note counts as none).
    @MainActor public static func text(for exerciseID: UUID, in context: ModelContext) -> String? {
        guard let note = notes(for: exerciseID, in: context).first, !note.text.isEmpty else { return nil }
        return note.text
    }

    /// Saves `text` (trimmed, capped at `maxLength`) as the exercise's note. Blank text clears it. Duplicates left by a
    /// CloudKit merge collapse into one row.
    @MainActor public static func set(_ text: String, for exerciseID: UUID, in context: ModelContext) throws {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        guard !trimmed.isEmpty else { return try clear(exerciseID, in: context) }
        let existing = notes(for: exerciseID, in: context)
        if let keep = existing.first {
            keep.text = trimmed
            keep.updatedAt = Date()
            for extra in existing.dropFirst() { context.delete(extra) }
        } else {
            context.insert(StickyNote(exerciseID: exerciseID, text: trimmed))
        }
        try context.save()
    }

    /// Deletes the exercise's note, if any.
    @MainActor public static func clear(_ exerciseID: UUID, in context: ModelContext) throws {
        let existing = notes(for: exerciseID, in: context)
        guard !existing.isEmpty else { return }
        for note in existing { context.delete(note) }
        try context.save()
    }

    @MainActor private static func notes(for exerciseID: UUID, in context: ModelContext) -> [StickyNote] {
        let descriptor = FetchDescriptor<StickyNote>(
            predicate: #Predicate { $0.exerciseID == exerciseID },
            sortBy: [SortDescriptor(\.updatedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
