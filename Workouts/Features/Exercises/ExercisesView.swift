//
//  ExercisesView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The Exercises tab (task 4.1a): a `NavigationSplitView` with the exercise list in the sidebar column and the exercise
/// detail in the detail column (`ExerciseDetailView`, 4.2). Compact width pushes the detail; regular width always shows
/// the list beside the detail (JC52), with "Select an Exercise" until a row is chosen. Search is `.searchable` only, over name and aliases. Two `Menu` pills (body part, category) lead the list; the
/// toolbar has New Exercise (the custom exercise form) and a Show Retired toggle.
struct ExercisesView: View {
    @Environment(ExerciseStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(filter: #Predicate<Workout> { $0.finishedAt != nil }) private var finished: [Workout]
    /// The newest edit among finished workouts: with the count it keys the best-set task without reading every workout.
    @Query(ExercisesView.newestEdit) private var newest: [Workout]
    // Read here only so a unit or formula change in Settings recomputes the best sets.
    @AppStorage(SettingsKey.defaultUnit.rawValue) private var unitRaw = ""
    @AppStorage(SettingsKey.e1rmFormula.rawValue) private var formulaRaw = ""
    @State private var query = ""
    @State private var selection: ExercisesRoute?
    @State private var bestSets: [UUID: String] = [:]
    @State private var bodyPart: String?
    @State private var category: String?
    @State private var showRetired = false
    @State private var isCreating = false
    @State private var naturalMatch: NaturalSearchMatch?
    @Namespace private var zoomNamespace

    var body: some View {
        // Regular width: the list column is permanent beside the detail, never behind a toggle (JC52). `.all` keeps it
        // shown; the binding's setter ignores the system's collapse requests. Compact width still pushes the detail.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            list
                // The list never collapses, so the system's show/hide button has nothing to do.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("screen.exercises")
        // Deleting the selected custom exercise empties the selection, which also pops the pushed detail on compact width.
        .onChange(of: selectionExists) { _, exists in
            if !exists { selection = nil }
        }
    }

    private static var newestEdit: FetchDescriptor<Workout> {
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.finishedAt != nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private var naturalResults: [ExerciseInfo] {
        guard let naturalMatch, naturalMatch.text == query else { return [] }
        return store.matches(naturalMatch.query, includeRetired: showRetired)
    }

    private var selectionExists: Bool {
        guard case .exercise(let id) = selection else { return true }
        return store.exercise(id: id) != nil
    }

    private var list: some View {
        let plain = store.search(query, includeRetired: showRetired)
        // Only when the plain search found nothing and the parser answered for this exact text (PLAN 4.6).
        let results = ExerciseFilter.apply(
            plain.isEmpty ? naturalResults : plain,
            bodyPart: bodyPart,
            category: category
        )
        let labels = store.catalog.labels
        return List(selection: $selection) {
            filterRow
            ForEach(results) { info in
                let subtitle = ExerciseFilter.subtitle(for: info, labels: labels)
                let best = bestSets[info.id] ?? ""
                ExerciseRow(info: info, subtitle: subtitle, trailing: best)
                    .tag(ExercisesRoute.exercise(info.id))
                    .matchedTransitionSource(id: info.id, in: zoomNamespace)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        [info.name, ExerciseRow.tagText(for: info), subtitle, best].filter { !$0.isEmpty }.joined(
                            separator: ", "
                        )
                    )
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("exercises.row.\(info.id.uuidString)")
            }
        }
        .listStyle(.plain)
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle("Exercises")
        .resumeControl()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Exercise", systemImage: "plus") { isCreating = true }
                    .accessibilityIdentifier("exercises.new")
            }
            ToolbarItem(placement: .primaryAction) {
                let title = showRetired ? "Hide Retired" : "Show Retired"
                Toggle(title, systemImage: showRetired ? "archivebox.fill" : "archivebox", isOn: $showRetired)
                    .toggleStyle(.button)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("exercises.showRetired")
            }
        }
        .sheet(isPresented: $isCreating) {
            CustomExerciseFormView()
                .presentationPlacement(.center)
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
        .naturalLanguageSearch(text: query, includeRetired: showRetired, match: $naturalMatch)
        .task(id: fingerprint) {
            bestSets = ExerciseBestSets.texts(
                from: ExerciseBestSets.sessions(from: finished) { store.exercise(id: $0)?.weightType },
                options: recordsOptions
            )
        }
    }

    /// The two "Any ..." pills as the first list row, like the picker's chip row.
    private var filterRow: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            FilterMenu(
                title: "Body Part",
                anyLabel: "Any Body Part",
                identifier: "exercises.filter.bodyPart",
                selection: $bodyPart,
                keys: { ExerciseFilter.bodyParts(in: store.all(includeRetired: true), labels: store.catalog.labels) },
                label: { ExerciseFilter.bodyPartLabel($0, labels: store.catalog.labels) }
            )
            FilterMenu(
                title: "Category",
                anyLabel: "Any Category",
                identifier: "exercises.filter.category",
                selection: $category,
                keys: { ExerciseFilter.categories(in: store.all(includeRetired: true), labels: store.catalog.labels) },
                label: { ExerciseFilter.equipmentLabel($0, labels: store.catalog.labels) }
            )
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    @ViewBuilder
    private var detail: some View {
        if case .exercise(let id) = selection, let info = store.exercise(id: id) {
            ExerciseDetailView(exerciseID: info.id)
                .id(info.id)
                .navigationTransition(.zoom(sourceID: info.id, in: zoomNamespace))
        } else {
            ContentUnavailableView(
                "Select an Exercise",
                systemImage: "figure.strengthtraining.traditional"
            )
            .accessibilityIdentifier("exercises.detail.empty")
        }
    }

    private var fingerprint: Fingerprint {
        Fingerprint(count: finished.count, newestEdit: newest.first?.updatedAt, unit: unitRaw, formula: formulaRaw)
    }

    private var recordsOptions: RecordsOptions {
        RecordsOptions(formula: settings.e1rmFormula, displayUnit: settings.defaultUnit)
    }
}

/// Changes when a finished workout is added, removed or edited, or a setting that changes the numbers does, so the best
/// sets are recomputed then and not per render. Built from a count and the newest `updatedAt` so no per-workout read runs
/// per body evaluation; every editor stamps `updatedAt` (`PastWorkoutDraft.apply`, the engine's finish).
private struct Fingerprint: Hashable {
    let count: Int
    let newestEdit: Date?
    let unit: String
    let formula: String
}

#if DEBUG
    #Preview("Large") {
        PreviewGallery.host("Exercises")
            .environment(SettingsStore())
            .dynamicTypeSize(.large)
    }

    #Preview("Accessibility 3") {
        PreviewGallery.host("Exercises")
            .environment(SettingsStore())
            .dynamicTypeSize(.accessibility3)
    }
#endif
