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
    /// Unfinished workouts in the file that were skipped because the store already has a different one in progress
    /// (they are also counted in `workouts.skipped`).
    public var skippedInProgress = 0

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

extension ImportError: LocalizedError {
    public nonisolated var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "This file uses format version \(version), which this version of the app cannot read."
        }
    }
}

extension ImportEntity {
    /// The label a person sees for this kind of row, or `nil` for child rows (sets, template and workout exercises)
    /// that only count as part of their parent.
    fileprivate nonisolated var displayName: String? {
        switch self {
        case .folders: "Folders"
        case .templates: "Templates"
        case .customExercises: "Custom exercises"
        case .stickyNotes: "Exercise notes"
        case .workouts: "Workouts"
        case .templateExercises, .templateSets, .workoutExercises, .workoutSets: nil
        }
    }
}

extension ImportReport {
    /// Short title for the result alert.
    public nonisolated var headline: String {
        changedAnything ? "Import Complete" : "Nothing New to Import"
    }

    /// Plain-text summary: one line per kind of row that appeared in the file ("Workouts: 3 added, 1 updated, 46
    /// skipped"), then a note for library exercises this build does not know and for broken links. Child rows are
    /// not listed; they follow their parent.
    public nonisolated var summary: String {
        var lines: [String] = []
        for entity in ImportEntity.allCases {
            guard let name = entity.displayName else { continue }
            let c = self[entity]
            guard c.inserted + c.updated + c.skipped + c.removed > 0 else { continue }
            lines.append("\(name): \(c.inserted) added, \(c.updated) updated, \(c.skipped) skipped")
        }
        if lines.isEmpty { lines.append("The file had no data.") }
        if !unknownLibraryRefs.isEmpty {
            let n = unknownLibraryRefs.count
            let noun = n == 1 ? "library exercise is" : "library exercises are"
            lines.append("\(n) \(noun) not in this version of the app; their names were kept.")
        }
        if danglingReferences > 0 {
            let noun = danglingReferences == 1 ? "link" : "links"
            lines.append("\(danglingReferences) \(noun) to a missing folder or template could not be restored.")
        }
        if skippedInProgress > 0 {
            lines.append(
                skippedInProgress == 1
                    ? "1 unfinished workout was skipped because one is in progress."
                    : "\(skippedInProgress) unfinished workouts were skipped because one is in progress."
            )
        }
        return lines.joined(separator: "\n")
    }
}
