//
//  FilterPillRow.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The "Any Body Part" / "Any Category" pills as one list row, shared by the Exercises tab and the picker. Side by side at
/// regular sizes; stacked and leading-aligned at accessibility sizes, where two pills no longer fit across.
struct FilterPillRow: View {
    /// Prefix of the pills' accessibility identifiers (`<prefix>.bodyPart`, `<prefix>.category`).
    let identifierPrefix: String
    /// Whether the pills offer keys of retired exercises too.
    let includeRetired: Bool
    @Binding var bodyPart: String?
    @Binding var category: String?

    @Environment(ExerciseStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        let labels = store.catalog.labels
        layout {
            FilterMenu(
                title: "Body Part",
                anyLabel: "Any Body Part",
                identifier: "\(identifierPrefix).bodyPart",
                selection: $bodyPart,
                keys: { ExerciseFilter.bodyParts(in: store.all(includeRetired: includeRetired), labels: labels) },
                label: { ExerciseFilter.bodyPartLabel($0, labels: labels) }
            )
            FilterMenu(
                title: "Category",
                anyLabel: "Any Category",
                identifier: "\(identifierPrefix).category",
                selection: $category,
                keys: { ExerciseFilter.categories(in: store.all(includeRetired: includeRetired), labels: labels) },
                label: { ExerciseFilter.equipmentLabel($0, labels: labels) }
            )
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

/// The empty state under an exercise list: the search one when text matched nothing, and a filter-specific one when the
/// text is empty and the pills are what excluded everything (the search one would blame the spelling). It never takes
/// touches, so the pills above stay tappable; they are the way to remove a filter.
struct NoExerciseResultsView: View {
    let query: String
    let hasFilter: Bool

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasFilter {
                ContentUnavailableView(
                    "No Matching Exercises",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try removing a filter.")
                )
                .accessibilityIdentifier("exercises.noMatchingFilters")
            } else {
                ContentUnavailableView.search(text: query)
            }
        }
        .allowsHitTesting(false)
    }
}
