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
        let results = ExerciseFilter.results(in: store, query: query, bodyPart: bodyPart, category: category)
        NavigationStack {
            List {
                filterRow
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
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search exercises")
            .accessibilityIdentifier("picker.search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("picker.cancel")
                }
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
            .sheet(item: $peeked) { info in
                ExerciseAboutView(info: info)
                    .presentationDetents([.medium, .large])
                    .presentationPlacement(.center)
            }
        }
        .accessibilityIdentifier("screen.exercisePicker")
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

    /// The two "Any ..." pills as the first list row, like a chip row.
    private var filterRow: some View {
        HStack(spacing: 8) {
            FilterMenu(
                title: "Body Part",
                anyLabel: "Any Body Part",
                identifier: "picker.filter.bodyPart",
                selection: $bodyPart,
                keys: { ExerciseFilter.bodyParts(in: store.all(), labels: store.catalog.labels) },
                label: { ExerciseFilter.bodyPartLabel($0, labels: store.catalog.labels) }
            )
            FilterMenu(
                title: "Category",
                anyLabel: "Any Category",
                identifier: "picker.filter.category",
                selection: $category,
                keys: { ExerciseFilter.categories(in: store.all(), labels: store.catalog.labels) },
                label: { ExerciseFilter.equipmentLabel($0, labels: store.catalog.labels) }
            )
            Spacer(minLength: 0)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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

    var body: some View {
        let subtitle = ExerciseFilter.subtitle(for: info, labels: labels)
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    if showsSelection {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .imageScale(.large)
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

            Button("About \(info.name)", systemImage: "questionmark.circle", action: about)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("About \(info.name)")
                .accessibilityIdentifier("picker.about.\(info.id.uuidString)")
        }
    }
}

/// The "?" peek: both thumbnail frames, name, body part and equipment, and the instructions when there are any. Library
/// exercises read them from the catalog, custom ones from their row. Plain text, no history or charts.
private struct ExerciseAboutView: View {
    let info: ExerciseInfo

    @Environment(ExerciseStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let labels = store.catalog.labels
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !info.isCustom {
                        HStack(spacing: 8) {
                            ExerciseThumbnail(id: info.id, phase: .start, height: 96)
                            ExerciseThumbnail(id: info.id, phase: .end, height: 96)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.name)
                            .font(.title2.bold())
                            .accessibilityIdentifier("about.name")
                        if !info.bodyPart.isEmpty {
                            Text(ExerciseFilter.bodyPartLabel(info.bodyPart, labels: labels))
                                .foregroundStyle(.secondary)
                        }
                        if !info.equipment.isEmpty {
                            Text(
                                info.equipment.map { ExerciseFilter.equipmentLabel($0, labels: labels) }
                                    .joined(separator: ", ")
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                    let steps = instructions
                    if steps.isEmpty {
                        Text("No instructions for this exercise.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Instructions").font(.headline)
                            ForEach(Array(steps.enumerated()), id: \.offset) { offset, step in
                                Text("\(offset + 1). \(step)")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("about.close")
                }
            }
        }
        .accessibilityIdentifier("screen.exerciseAbout")
    }

    private var instructions: [String] {
        if !info.isCustom {
            return store.catalog.exercise(id: info.id)?.instructions ?? []
        }
        let id = info.id
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.instructions ?? []
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
