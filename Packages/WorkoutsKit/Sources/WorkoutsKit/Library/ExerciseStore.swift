import Foundation
import Observation
import SwiftData

/// What the UI may do to an exercise that the user asks to remove.
public nonisolated enum ExerciseRemoval: Sendable, Hashable {
    /// A custom exercise nothing references: delete the row.
    case delete
    /// A custom exercise history references: set `retired` instead.
    case archive
    /// A library exercise (read-only) or an unknown id.
    case notAllowed
}

/// Library catalog union custom exercises: lookup by id, name-sorted list and all-words search.
///
/// Built from values (a catalog and an array of custom `Exercise` rows); it never queries SwiftData. Call
/// `setCustom(_:)` whenever the rows change.
@Observable
public final class ExerciseStore {
    public let catalog: LibraryCatalog
    private var byID: [UUID: ExerciseInfo] = [:]
    /// Exercise id to weight type, a Sendable copy for work that runs off the main actor (`WorkoutStatsReader`).
    public private(set) var weightTypes: [UUID: WeightType] = [:]
    private var sorted: [ExerciseInfo] = []
    /// Folded search haystacks (name, then aliases), parallel to `sorted`.
    private var haystacks: [[String]] = []

    public init(catalog: LibraryCatalog, custom: [Exercise] = []) {
        self.catalog = catalog
        rebuild(custom: custom.map(ExerciseInfo.init))
    }

    /// Replaces the custom exercises (call after any insert, edit, archive or delete).
    public func setCustom(_ custom: [Exercise]) {
        rebuild(custom: custom.map(ExerciseInfo.init))
    }

    /// Re-reads every custom exercise from `context` into the store: for changes the app did not make itself (a custom
    /// exercise CloudKit merged in from another device).
    public func reloadCustom(from context: ModelContext) throws {
        setCustom(try context.fetch(FetchDescriptor<Exercise>()))
    }

    /// Library or custom exercise with this id, retired ones included. A custom row wins over a library
    /// row with the same id (ids never collide in practice).
    public func exercise(id: UUID) -> ExerciseInfo? {
        byID[id]
    }

    /// Exercises sorted by name (localized, case- and diacritic-insensitive, ties by id).
    public func all(includeRetired: Bool = false) -> [ExerciseInfo] {
        includeRetired ? sorted : sorted.filter { !$0.isRetired }
    }

    /// Every whitespace-separated word of `query` must be a case- and accent-insensitive substring of the
    /// name or of any alias (words may match different fields). An empty query returns `all`.
    public func search(_ query: String, includeRetired: Bool = false) -> [ExerciseInfo] {
        let words = Self.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return all(includeRetired: includeRetired) }
        var result: [ExerciseInfo] = []
        for (offset, info) in sorted.enumerated() where includeRetired || !info.isRetired {
            let fields = haystacks[offset]
            if words.allSatisfy({ word in fields.contains { $0.contains(word) } }) {
                result.append(info)
            }
        }
        return result
    }

    /// A custom exercise may be deleted only when no history references it (otherwise archive it).
    public nonisolated static func canDelete(customID: UUID, referencedIDs: Set<UUID>) -> Bool {
        !referencedIDs.contains(customID)
    }

    /// What removing `id` means: delete, archive, or nothing for library and unknown ids.
    public func removal(of id: UUID, referencedIDs: Set<UUID>) -> ExerciseRemoval {
        guard let info = byID[id], info.isCustom else { return .notAllowed }
        return Self.canDelete(customID: id, referencedIDs: referencedIDs) ? .delete : .archive
    }

    /// Lowercased, diacritic-stripped form used for matching.
    public nonisolated static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private func rebuild(custom: [ExerciseInfo]) {
        var merged: [UUID: ExerciseInfo] = [:]
        for exercise in catalog.exercises { merged[exercise.id] = ExerciseInfo(exercise) }
        for info in custom { merged[info.id] = info }
        let ordered = merged.values.sorted { lhs, rhs in
            let order = lhs.name.compare(
                rhs.name,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: nil,
                locale: .current
            )
            return order == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : order == .orderedAscending
        }
        byID = merged
        weightTypes = merged.mapValues(\.weightType)
        sorted = ordered
        haystacks = ordered.map { info in ([info.name] + info.aliases).map(Self.fold) }
    }
}
