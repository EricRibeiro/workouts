import Foundation

/// The kinds of rows ``Importer`` reports on.
public nonisolated enum ImportEntity: String, CaseIterable, Sendable {
    case folders
    case templates
    case templateExercises
    case templateSets
    case customExercises
    case stickyNotes
    case workouts
    case workoutExercises
    case workoutSets
}

/// What happened to one kind of row.
public nonisolated struct ImportCounts: Hashable, Sendable {
    /// Rows created because no row with the id existed.
    public var inserted = 0
    /// Existing rows overwritten from the document.
    public var updated = 0
    /// Rows left alone because the store's copy is as new or newer (children follow their parent).
    public var skipped = 0
    /// Local children deleted because the document's copy of the parent no longer lists them.
    public var removed = 0

    public init(inserted: Int = 0, updated: Int = 0, skipped: Int = 0, removed: Int = 0) {
        self.inserted = inserted
        self.updated = updated
        self.skipped = skipped
        self.removed = removed
    }
}

/// A library reference the catalog does not contain (a newer or removed library entry).
public nonisolated struct UnknownLibraryRef: Hashable, Sendable {
    public var source: String
    public var sourceId: String
    /// The `exerciseName` snapshots seen for it, sorted. Empty when only sticky notes use it.
    public var names: [String]
    /// How many template exercises, workout exercises and sticky notes point at it.
    public var uses: Int

    public init(source: String, sourceId: String, names: [String], uses: Int) {
        self.source = source
        self.sourceId = sourceId
        self.names = names
        self.uses = uses
    }
}

/// The result of ``Importer/apply(_:to:catalog:)``.
public nonisolated struct ImportReport: Equatable, Sendable {
    public var counts: [ImportEntity: ImportCounts] = [:]
    /// Library references the catalog could not resolve, sorted by `source`, `sourceId`. The rows were
    /// still imported (with their `exerciseName` snapshot and the `LibraryID` of the reference).
    public var unknownLibraryRefs: [UnknownLibraryRef] = []
    /// `folderId` / `templateId` values that matched no folder or template; the relationship is left nil.
    public var danglingReferences = 0

    public init() {}

    public subscript(entity: ImportEntity) -> ImportCounts {
        get { counts[entity] ?? ImportCounts() }
        set { counts[entity] = newValue }
    }

    /// The counts summed across every kind of row.
    public var totals: ImportCounts {
        var total = ImportCounts()
        for value in counts.values {
            total.inserted += value.inserted
            total.updated += value.updated
            total.skipped += value.skipped
            total.removed += value.removed
        }
        return total
    }

    /// True when the import wrote anything (inserted, updated or removed a row).
    public var changedAnything: Bool {
        let total = totals
        return total.inserted + total.updated + total.removed > 0
    }
}

/// Why an import was refused before touching the store.
public nonisolated enum ImportError: Error, Equatable, Sendable {
    /// The document's `version` is not one this build reads.
    case unsupportedVersion(Int)
}
