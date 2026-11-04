import Foundation

/// Pure filtering and display helpers for the exercise picker and the Exercises list.
///
/// Two filters exist: body part (`ExerciseInfo.bodyPart`) and category (= equipment: an exercise matches when any of its
/// `equipment` keys equals the chosen one). `nil` means "Any".
public nonisolated enum ExerciseFilter {
    /// Keeps the exercises that match both filters, preserving order.
    public static func apply(
        _ exercises: [ExerciseInfo],
        bodyPart: String? = nil,
        category: String? = nil
    ) -> [ExerciseInfo] {
        guard bodyPart != nil || category != nil else { return exercises }
        return exercises.filter { info in
            let bodyPartMatches = bodyPart.map { info.bodyPart == $0 } ?? true
            let categoryMatches = category.map { info.equipment.contains($0) } ?? true
            return bodyPartMatches && categoryMatches
        }
    }

    /// Body part keys in use, sorted by display label. Empty keys are skipped.
    public static func bodyParts(in exercises: [ExerciseInfo], labels: LibraryLabels) -> [String] {
        sortedByLabel(Set(exercises.map(\.bodyPart))) { bodyPartLabel($0, labels: labels) }
    }

    /// Equipment (category) keys in use, sorted by display label.
    public static func categories(in exercises: [ExerciseInfo], labels: LibraryLabels) -> [String] {
        sortedByLabel(Set(exercises.flatMap(\.equipment))) { equipmentLabel($0, labels: labels) }
    }

    /// Display name of a body part key; unknown keys (custom exercises) are humanised.
    public static func bodyPartLabel(_ key: String, labels: LibraryLabels) -> String {
        labels.bodyParts[key] ?? humanised(key)
    }

    /// Display name of an equipment key; unknown keys are humanised.
    public static func equipmentLabel(_ key: String, labels: LibraryLabels) -> String {
        labels.equipment[key] ?? humanised(key)
    }

    /// Secondary row line: "Body part · Equipment, Equipment". Empty parts are left out.
    public static func subtitle(for info: ExerciseInfo, labels: LibraryLabels) -> String {
        var parts: [String] = []
        if !info.bodyPart.isEmpty { parts.append(bodyPartLabel(info.bodyPart, labels: labels)) }
        if !info.equipment.isEmpty {
            parts.append(info.equipment.map { equipmentLabel($0, labels: labels) }.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    /// Search first (name and aliases, all words), then both filters. Retired exercises are hidden.
    @MainActor
    public static func results(
        in store: ExerciseStore,
        query: String,
        bodyPart: String? = nil,
        category: String? = nil
    ) -> [ExerciseInfo] {
        apply(store.search(query), bodyPart: bodyPart, category: category)
    }

    private static func sortedByLabel(_ keys: Set<String>, label: (String) -> String) -> [String] {
        keys.filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                let order = label(lhs).localizedCaseInsensitiveCompare(label(rhs))
                return order == .orderedSame ? lhs < rhs : order == .orderedAscending
            }
    }

    private static func humanised(_ key: String) -> String {
        let spaced = key.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
