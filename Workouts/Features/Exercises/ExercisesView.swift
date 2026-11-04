//
//  ExercisesView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The Exercises tab (task 4.1a): a `NavigationSplitView` with the exercise list in the content column and the exercise
/// detail in the detail column (a placeholder until 4.2). Compact width pushes the detail; regular width shows it beside
/// the list. Search is `.searchable` only, over name and aliases; retired exercises are hidden (Show Retired is 4.1b).
struct ExercisesView: View {
    @Environment(ExerciseStore.self) private var store
    @Query(filter: #Predicate<Workout> { $0.finishedAt != nil }) private var finished: [Workout]
    @State private var query = ""
    @State private var selection: ExercisesRoute?
    @State private var bestSets: [UUID: String] = [:]

    var body: some View {
        NavigationSplitView {
            list
        } detail: {
            detail
        }
        .accessibilityIdentifier("screen.exercises")
    }

    private var list: some View {
        let results = ExerciseFilter.results(in: store, query: query)
        let labels = store.catalog.labels
        return List(selection: $selection) {
            ForEach(results) { info in
                let subtitle = ExerciseFilter.subtitle(for: info, labels: labels)
                let best = bestSets[info.id] ?? ""
                ExerciseRow(info: info, subtitle: subtitle, trailing: best)
                    .tag(ExercisesRoute.exercise(info.id))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel([info.name, subtitle, best].filter { !$0.isEmpty }.joined(separator: ", "))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("exercises.row.\(info.id.uuidString)")
            }
        }
        .listStyle(.plain)
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Exercises")
        .searchable(text: $query, prompt: "Search exercises")
        .task(id: Fingerprint(finished)) {
            bestSets = ExerciseBestSets.texts(
                from: ExerciseBestSets.sessions(from: finished) { store.exercise(id: $0)?.weightType },
                options: recordsOptions
            )
        }
    }

    @ViewBuilder
    private var detail: some View {
        if case .exercise(let id) = selection, let info = store.exercise(id: id) {
            // Placeholder until the real detail (4.2).
            ContentUnavailableView(
                info.name,
                systemImage: "figure.strengthtraining.traditional",
                description: Text("Exercise details are coming soon.")
            )
            .navigationTitle(info.name)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("exercises.detail")
        } else {
            ContentUnavailableView(
                "Select an Exercise",
                systemImage: "figure.strengthtraining.traditional"
            )
            .accessibilityIdentifier("exercises.detail.empty")
        }
    }

    private var recordsOptions: RecordsOptions {
        let settings = SettingsStore()
        return RecordsOptions(formula: settings.e1rmFormula, displayUnit: settings.defaultUnit)
    }
}

/// Changes when a finished workout is added, removed or edited, so the best sets are recomputed then and not per render.
private struct Fingerprint: Hashable {
    let count: Int
    let newestEdit: Date?

    init(_ workouts: [Workout]) {
        count = workouts.count
        newestEdit = workouts.map(\.updatedAt).max()
    }
}

#if DEBUG
    #Preview("Large") {
        PreviewGallery.host("Exercises")
            .dynamicTypeSize(.large)
    }

    #Preview("Accessibility 3") {
        PreviewGallery.host("Exercises")
            .dynamicTypeSize(.accessibility3)
    }
#endif
