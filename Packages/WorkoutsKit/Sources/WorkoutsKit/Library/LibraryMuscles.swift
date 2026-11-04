//
//  LibraryMuscles.swift
//  WorkoutsKit
//

import Foundation

/// How the About block shows a library exercise's muscle intensity map (`docs/port/screens/exercises.md`).
public nonisolated enum LibraryMuscles {
    /// Intensity at or above this is a primary muscle (our choice, not the source's).
    public static let primaryThreshold = 70

    /// Intensity >= 70 is primary, 1-69 secondary, 0 dropped; strongest first, ties by label.
    public static func split(_ muscles: [String: Int], labels: LibraryLabels) -> (
        primary: [String], secondary: [String]
    ) {
        let ordered =
            muscles
            .filter { $0.value > 0 }
            .map { (label: label($0.key, labels: labels), intensity: $0.value) }
            .sorted { $0.intensity != $1.intensity ? $0.intensity > $1.intensity : $0.label < $1.label }
        return (
            ordered.filter { $0.intensity >= primaryThreshold }.map(\.label),
            ordered.filter { $0.intensity < primaryThreshold }.map(\.label)
        )
    }

    /// The catalog label, else the key made readable ("chest_upper" becomes "Chest upper").
    public static func label(_ key: String, labels: LibraryLabels) -> String {
        if let label = labels.muscles[key], !label.isEmpty { return label }
        let words = key.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
