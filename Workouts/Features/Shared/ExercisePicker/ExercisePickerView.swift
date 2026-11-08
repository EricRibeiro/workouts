//
//  ExercisePickerView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// How the picker hands its result back.
enum ExercisePickerMode {
    /// Add and Replace of one exercise: tapping a row picks it and closes the sheet.
    case single((ExerciseInfo) -> Void)
    /// Rows toggle a checkmark; **Add (N)** adds them plain, **Superset** (two or more) adds them as one group. Both
    /// receive the exercises in tick order and close the sheet.
    case multiple(add: ([ExerciseInfo]) -> Void, superset: ([ExerciseInfo]) -> Void)
}

/// Reusable exercise picker (tasks 2.1a, 2.1b): single-select for Replace, multi-select for Add Exercise. Present it in a
/// sheet; on regular width the presenter names `presentationPlacement(.center)`.
///
/// Reads the `ExerciseStore` from the environment. Search, body part, category and the ticked rows are kept only while the
/// sheet lives. A trailing `?` button on every row opens the lightweight "About" peek.
struct ExercisePickerView: View {
    let title: String
    let mode: ExercisePickerMode

    @Environment(ExerciseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var bodyPart: String?
    @State private var category: String?
    @State private var selection = ExerciseSelection()
    @State private var peeked: ExerciseInfo?
    @State private var isCreating = false
    @State private var naturalMatch: NaturalSearchMatch?

    init(title: String = "Add Exercise", mode: ExercisePickerMode) {
        self.title = title
        self.mode = mode
    }

    /// Single-select, as 2.1a.
    init(title: String = "Add Exercise", onPick: @escaping (ExerciseInfo) -> Void) {
        self.init(title: title, mode: .single(onPick))
    }

    private var isMultiple: Bool {
        if case .multiple = mode { return true }
        return false
    }

    var body: some View {
        let plain = store.search(query)
        // Only when the plain search found nothing and the parser answered for this exact text (PLAN 4.6).
        let results = ExerciseFilter.apply(
            plain.isEmpty ? naturalResults : plain,
            bodyPart: bodyPart,
            category: category
        )
        NavigationStack {
            List {
                FilterPillRow(
                    identifierPrefix: "picker.filter",
                    includeRetired: false,
                    bodyPart: $bodyPart,
                    category: $category
                )
                createRow
                ForEach(results) { info in
                    ExercisePickerRow(
                        info: info,
                        labels: store.catalog.labels,
                        showsSelection: isMultiple,
                        isSelected: selection.contains(info.id),
                        action: { tap(info) },
                        about: { peeked = info }
                    )
                }
            }
            .listStyle(.plain)
            .overlay {
                if results.isEmpty {
                    NoExerciseResultsView(query: query, hasFilter: bodyPart != nil || category != nil)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search exercises")
            .naturalLanguageSearch(text: query, match: $naturalMatch)
            .accessibilityIdentifier("picker.search")
            .toolbar {
                CancelToolbarItem(id: "picker.cancel") { dismiss() }
                if case .multiple(let add, let superset) = mode {
                    ToolbarItem(placement: .confirmationAction) {
                        let label = selection.canAdd ? "Add \(selection.count)" : "Add"
                        Button(label, systemImage: "plus") {
                            finish(add)
                        }
                        .disabled(!selection.canAdd)
                        .accessibilityLabel(label)
                        .accessibilityIdentifier("picker.add")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Superset", systemImage: "rectangle.stack") {
                            finish(superset)
                        }
                        .disabled(!selection.canSuperset)
                        .accessibilityLabel("Superset")
                        .accessibilityIdentifier("picker.superset")
                    }
                }
            }
            .sheet(isPresented: $isCreating) {
                CustomExerciseFormView(prefill: trimmedQuery) { created in
                    switch mode {
                    case .single(let onPick):
                        onPick(created)
                        dismiss()
                    case .multiple:
                        selection.select(created.id)
                    }
                }
                .presentationPlacement(.center)
            }
            .sheet(item: $peeked) { info in
                ExercisePeekSheet(exerciseID: info.id)
                    .presentationDetents([.medium, .large])
                    .presentationPlacement(.center)
            }
        }
        .accessibilityIdentifier("screen.exercisePicker")
    }

    private var naturalResults: [ExerciseInfo] {
        guard let naturalMatch, naturalMatch.text == query else { return [] }
        return store.matches(naturalMatch.query)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The spec's **New** control, always available: opens the custom exercise form, with the search text as the name when
    /// there is one, and the saved exercise is ticked (multi) or picked (single). It is a list row, not a toolbar item,
    /// because the toolbar is hidden while a search is active, which is exactly when the text to prefill exists (and on
    /// the closed Duo the trailing strip is already full with Add and Superset). With no results it is the row to reach for,
    /// above the "No Results" overlay (which never takes touches).
    private var createRow: some View {
        let label = trimmedQuery.isEmpty ? "New Exercise" : "Create “\(trimmedQuery)”"
        return Button(label, systemImage: "plus.circle") { isCreating = true }
            .accessibilityLabel(label)
            .accessibilityIdentifier("picker.createCustom")
    }

    private func tap(_ info: ExerciseInfo) {
        switch mode {
        case .single(let onPick):
            onPick(info)
            dismiss()
        case .multiple:
            selection.toggle(info.id)
        }
    }

    private func finish(_ handler: ([ExerciseInfo]) -> Void) {
        handler(selection.resolve { store.exercise(id: $0) })
        dismiss()
    }
}

/// A light row: optional checkmark, thumbnail, name, "Body part · Equipment", and a trailing `?` button for the peek.
/// The rest of the row is the select button.
private struct ExercisePickerRow: View {
    let info: ExerciseInfo
    let labels: LibraryLabels
    let showsSelection: Bool
    let isSelected: Bool
    let action: () -> Void
    let about: () -> Void

    @ScaledMetric(relativeTo: .body) private var glyphWidth = 28.0

    var body: some View {
        let subtitle = ExerciseFilter.subtitle(for: info, labels: labels)
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    if showsSelection {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .imageScale(.large)
                            .frame(width: glyphWidth)
                            .accessibilityHidden(true)
                    }
                    ExerciseRow(info: info, subtitle: subtitle)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                [info.name, ExerciseRow.tagText(for: info), subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
            )
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("picker.row.\(info.id.uuidString)")

            Button("About \(info.name)", systemImage: "info.circle", action: about)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("About \(info.name)")
                .accessibilityIdentifier("picker.about.\(info.id.uuidString)")
        }
    }
}

/// The "?" peek: the exercise detail itself (About, History, Charts, Records), embedded in a sheet with a Close button.
private struct ExercisePeekSheet: View {
    let exerciseID: UUID

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseDetailView(exerciseID: exerciseID, embedded: true)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .accessibilityLabel("Close")
                            .accessibilityIdentifier("about.close")
                    }
                }
        }
        .accessibilityIdentifier("screen.exerciseAbout")
        // Its detail can report a save failure (the pre-load flush): the root's alert sits under this sheet, so host it here.
        .sheetSaveErrorHost()
    }
}

#if DEBUG
    #Preview("Single") {
        PreviewGallery.host("ExercisePicker")
    }

    #Preview("Multiple") {
        PreviewGallery.host("ExercisePickerMulti")
    }
#endif
