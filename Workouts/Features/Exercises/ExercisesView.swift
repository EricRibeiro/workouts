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
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The newest edit among finished workouts: with the store generation it keys the best-set task without reading every
    /// workout. A delete or an import that updates an older workout bumps the generation.
    @Query(Workout.newestFinishedEdit) private var newest: [Workout]
    @Environment(StoreGeneration.self) private var generation: StoreGeneration?
    @Environment(SaveErrors.self) private var saveErrors: SaveErrors?
    // Read here only so a unit or formula change in Settings recomputes the best sets.
    @AppStorage(SettingsKey.defaultUnit.rawValue) private var unitRaw = ""
    @AppStorage(SettingsKey.e1rmFormula.rawValue) private var formulaRaw = ""
    @AppStorage(SettingsKey.fullExerciseNames.rawValue) private var fullNames = SettingsStore
        .fullExerciseNamesDefault
    @State private var query = ""
    @State private var selection: ExercisesRoute?
    @State private var bestSets: [UUID: String] = [:]
    @State private var bodyPart: String?
    @State private var category: String?
    @State private var showRetired = false
    @State private var isCreating = false
    @State private var naturalMatch: NaturalSearchMatch?
    @FocusState private var isSearchFocused: Bool
    @Namespace private var zoomNamespace

    var body: some View {
        // Regular width: the list column is permanent beside the detail, never behind a toggle (JC52). `.all` keeps it
        // shown; the binding's setter ignores the system's collapse requests. Compact width still pushes the detail.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            list
                // The list never collapses, so the system's show/hide button has nothing to do.
                .toolbar(removing: .sidebarToggle)
                // `.balanced` splits the width evenly, which leaves the list ~230pt on the tall open Duo: names hyphen-wrap and
                // the filter pills truncate. A 320pt minimum keeps the list readable (`ideal` is required by the API, so it
                // matches the minimum); there is no max, so the system can still size the columns to the fold when half-open.
                .navigationSplitViewColumnWidth(min: 320, ideal: 320)
        } detail: {
            // The detail crosses the fold on the open Duo on purpose (JC133): widening the list to the fold makes the system
            // overlay it, and insetting the detail past the fold costs a third of its width.
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .dismissSearchKeyboardOnTap($isSearchFocused)
        .accessibilityIdentifier("screen.exercises")
        // Deleting the selected custom exercise empties the selection, which also pops the pushed detail on compact width.
        .onChange(of: selectionExists) { _, exists in
            if !exists { selection = nil }
        }
    }

    private var naturalResults: [ExerciseInfo] {
        guard let naturalMatch, naturalMatch.text == query else { return [] }
        return store.matches(naturalMatch.query, includeRetired: showRetired)
    }

    private var selectionExists: Bool {
        guard case .exercise(let id) = selection else { return true }
        return store.exercise(id: id) != nil
    }

    private var listFill: Color {
        Color(horizontalSizeClass == .regular ? .secondarySystemBackground : .systemBackground)
    }

    /// A custom row background replaces the system's selection highlight, so the selected row at regular width draws its own:
    /// an inset rounded fill, like a sidebar's selection.
    @ViewBuilder
    private func rowBackground(selected: Bool) -> some View {
        if selected && horizontalSizeClass == .regular {
            ZStack {
                listFill
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.fill.secondary)
                    .padding(.horizontal, 8)
            }
        } else {
            listFill
        }
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
            FilterPillRow(
                identifierPrefix: "exercises.filter",
                includeRetired: true,
                bodyPart: $bodyPart,
                category: $category
            )
            .listRowBackground(listFill)
            ForEach(results) { info in
                let subtitle = ExerciseFilter.subtitle(for: info, labels: labels)
                let best = bestSets[info.id] ?? ""
                ExerciseRow(info: info, subtitle: subtitle, trailing: best, fullNames: fullNames)
                    .tag(ExercisesRoute.exercise(info.id))
                    .listRowBackground(rowBackground(selected: selection == .exercise(info.id)))
                    .accessibilityAddTraits(selection == .exercise(info.id) ? .isSelected : [])
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
        // Beside the detail (regular width) the list column is a pane in the cards' fill; alone on the closed display it is the
        // screen, black like the other tabs. The split view fills its columns with the `.navigation` background (the sidebar
        // material by default); the `.navigationSplitView` placement only colours what sits behind them.
        .scrollContentBackground(.hidden)
        .background(listFill, ignoresSafeAreaEdges: .all)
        .containerBackground(listFill, for: .navigation)
        .overlay {
            if results.isEmpty {
                NoExerciseResultsView(query: query, hasFilter: bodyPart != nil || category != nil)
            }
        }
        .navigationTitle("Exercises")
        // Large in the bar row like the Workout tab, at both widths.
        .toolbarTitleDisplayMode(.inlineLarge)
        .resumeControl()
        .settingsControl()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Exercise", systemImage: "plus") { isCreating = true }
                    .accessibilityIdentifier("exercises.new")
            }
            ToolbarItem(placement: .primaryAction) {
                let title = showRetired ? "Hide Retired" : "Show Retired"
                Toggle(title, systemImage: showRetired ? "archivebox.fill" : "archivebox", isOn: $showRetired)
                    .toggleStyle(.button)
                    .accessibilityLabel("Show Retired Exercises")
                    .accessibilityIdentifier("exercises.showRetired")
            }
        }
        .sheet(isPresented: $isCreating) {
            CustomExerciseFormView()
                .presentationPlacement(.center)
        }
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search exercises"
        )
        .searchFocused($isSearchFocused)
        .naturalLanguageSearch(text: query, includeRetired: showRetired, match: $naturalMatch)
        .task(id: fingerprint) {
            await refreshBestSets()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if case .exercise(let id) = selection, let info = store.exercise(id: id) {
            ExerciseDetailView(exerciseID: info.id, inSplitColumn: true)
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

    /// Walks the history on a `WorkoutStatsReader` (its own context, off the main thread) and publishes the result here.
    /// The texts already shown stay until the new ones arrive, so a refresh never blanks the rows.
    private func refreshBestSets() async {
        // The reader's context reads the store: flush edits the main context has not saved yet.
        context.saveIfChanged(reportingTo: saveErrors)
        let texts = try? await WorkoutStatsReader.loadBestSetTexts(
            in: context.container,
            weightTypes: store.weightTypes,
            options: recordsOptions
        )
        guard !Task.isCancelled, let texts else { return }
        bestSets = texts
    }

    private var fingerprint: Fingerprint {
        Fingerprint(
            history: FinishedWorkoutsStamp(newestEdit: newest.first?.updatedAt, generation: generation?.value ?? 0),
            unit: unitRaw,
            formula: formulaRaw,
            weightTypes: store.weightTypes
        )
    }

    private var recordsOptions: RecordsOptions {
        RecordsOptions(formula: settings.e1rmFormula, displayUnit: settings.defaultUnit)
    }
}

/// Changes when a finished workout is added, removed or edited, or a setting or an exercise's weight type that changes the numbers does, so the best
/// sets are recomputed then and not per render. Built from the newest `updatedAt` and the `StoreGeneration` so no
/// per-workout read runs per body evaluation; every editor stamps `updatedAt` (`PastWorkoutDraft.apply`, the engine's
/// finish) and the bulk writes (import, delete) bump the generation.
private struct Fingerprint: Hashable {
    let history: FinishedWorkoutsStamp
    let unit: String
    let formula: String
    /// A custom exercise's weight type edit changes what its best set is.
    let weightTypes: [UUID: WeightType]
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
