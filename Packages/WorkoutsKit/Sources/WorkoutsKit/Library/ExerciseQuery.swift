import Foundation

/// A structured exercise search, the target of the natural-language parser (PLAN 4.6).
///
/// The app's Foundation Models parser turns a sentence ("something for rear delts with dumbbells") into one of
/// these; `ExerciseStore.matches(_:includeRetired:)` runs it. The kit only defines the value and the matching, it
/// never imports FoundationModels. JSON keys are `bodyParts`, `categories`, `equipment` and `words`.
///
/// Facet values are catalog keys (`"legs"`, `"dumbbell"`) or their human labels (`"Legs"`, `"Dumbbells"`), in any
/// case and with or without diacritics. `categories` is the equipment-category facet of `ExerciseFilter`, matched
/// against the exercise's `equipment` keys exactly like `equipment`; the two facets are separate so the model can
/// fill either, and an exercise must satisfy each non-empty one.
public nonisolated struct ExerciseQuery: Codable, Sendable, Hashable {
    public var bodyParts: [String]
    public var categories: [String]
    public var equipment: [String]
    public var words: [String]

    public init(
        bodyParts: [String] = [],
        categories: [String] = [],
        equipment: [String] = [],
        words: [String] = []
    ) {
        self.bodyParts = bodyParts
        self.categories = categories
        self.equipment = equipment
        self.words = words
    }

    /// True when no facet or word carries anything (blank and whitespace-only strings count as nothing).
    /// An empty query matches like the plain search with no words: every exercise.
    public var isEmpty: Bool {
        [bodyParts, categories, equipment, words].allSatisfy { $0.allSatisfy(Self.isBlank) }
    }

    fileprivate nonisolated static func isBlank(_ value: String) -> Bool {
        value.allSatisfy(\.isWhitespace)
    }
}

extension ExerciseStore {
    /// Exercises satisfying `query`, sorted by name like `search` and `all`.
    ///
    /// Rules:
    /// - Every non-empty facet must be satisfied (AND across facets); within a facet any value may match (OR):
    ///   body part is one of `bodyParts`, any of the exercise's equipment keys is one of `categories`, and any
    ///   is one of `equipment`.
    /// - `words` are joined and matched with the all-words search over name and aliases (`search(_:)`).
    /// - A facet value matches an exercise's key or its human label (the catalog's `labels`, or the humanised key
    ///   for custom values), compared case-, diacritic- and `_`/`-`/space-insensitively.
    /// - Blank strings are ignored. A facet whose values are all blank counts as unspecified.
    /// - Unknown values never fall back to "everything": a facet with values but no exercise matching any of them
    ///   matches nothing, so a bad parse yields no results. (A facet mixing a known and an unknown value still
    ///   matches by the known one.)
    /// - An empty query returns `all(includeRetired:)`.
    public func matches(_ query: ExerciseQuery, includeRetired: Bool = false) -> [ExerciseInfo] {
        let bodyParts = Self.queryTokens(query.bodyParts)
        let categories = Self.queryTokens(query.categories)
        let equipment = Self.queryTokens(query.equipment)
        let labels = catalog.labels
        let wordText = query.words.joined(separator: " ")
        return search(wordText, includeRetired: includeRetired).filter { info in
            if !bodyParts.isEmpty {
                let names = [info.bodyPart, ExerciseFilter.bodyPartLabel(info.bodyPart, labels: labels)]
                guard Self.anyMatch(names, in: bodyParts) else { return false }
            }
            for facet in [categories, equipment] where !facet.isEmpty {
                let names = info.equipment.flatMap { [$0, ExerciseFilter.equipmentLabel($0, labels: labels)] }
                guard Self.anyMatch(names, in: facet) else { return false }
            }
            return true
        }
    }

    private nonisolated static func queryTokens(_ values: [String]) -> Set<String> {
        Set(values.filter { !ExerciseQuery.isBlank($0) }.map(normalised))
    }

    private nonisolated static func anyMatch(_ names: [String], in tokens: Set<String>) -> Bool {
        names.contains { !$0.isEmpty && tokens.contains(normalised($0)) }
    }

    /// `fold` plus separators unified and trimmed: "Rear_Delts", "rear-delts" and " rear delts " all agree.
    private nonisolated static func normalised(_ value: String) -> String {
        fold(value)
            .split(whereSeparator: { $0.isWhitespace || $0 == "_" || $0 == "-" })
            .joined(separator: " ")
    }
}
