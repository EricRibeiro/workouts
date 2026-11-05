//
//  WorkoutDetailView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The workout detail (task 5.5), pushed from a History row with the zoom transition: the date, duration, volume and
/// PR count, the workout note, then one block per exercise with its completed sets (a trophy on the sets that set a
/// record) and a line per record. The bar has Edit (pushes the past-workout editor, 5.6), Save as Template and Delete. Everything shown is derived on read by
/// `WorkoutDetail` in the kit.
struct WorkoutDetailView: View {
    let workoutID: UUID

    @Environment(ExerciseStore.self) private var store
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Workout> { $0.finishedAt != nil }) private var finished: [Workout]

    @State private var isTemplatePresented = false
    @State private var isDeleteConfirming = false
    @State private var deleteFailed = false
    @State private var isDeleted = false
    @State private var savedTemplates = 0
    /// Derived in `.task(id:)` when the history or a setting changes, never in `body`.
    @State private var detail: WorkoutDetail?
    @State private var isLoaded = false

    var body: some View {
        ZStack {
            if let detail {
                content(detail)
            } else if isLoaded && !isDeleted {
                ContentUnavailableView(
                    "Workout Not Found",
                    systemImage: "questionmark.folder",
                    description: Text("That workout does not exist.")
                )
                .accessibilityIdentifier("history.detail.missing")
            }
        }
        .task(id: Inputs(finished, unit: settings?.defaultUnit, formula: settings?.e1rmFormula)) {
            detail = isDeleted ? nil : makeDetail()
            isLoaded = true
        }
        .sensoryFeedback(.success, trigger: savedTemplates)
        .alert("Could not delete the workout.", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func makeDetail() -> WorkoutDetail? {
        WorkoutDetail.make(
            id: workoutID,
            from: finished,
            weightType: { store.exercise(id: $0)?.weightType },
            options: RecordsOptions(
                formula: settings?.e1rmFormula ?? SettingsStore.e1rmFormulaDefault,
                displayUnit: settings?.defaultUnit ?? SettingsStore.defaultUnitDefault
            )
        )
    }

    private var workout: Workout? {
        finished.first { $0.id == workoutID }
    }

    // MARK: Content

    private func content(_ detail: WorkoutDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailHeader(detail: detail)
                ForEach(detail.exercises) { block in
                    ExerciseBlockView(block: block)
                }
                if detail.exercises.isEmpty {
                    Text("No completed sets in this workout.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle(detail.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: HistoryRoute.editWorkout(workoutID)) {
                    Label("Edit", systemImage: "pencil")
                }
                .accessibilityLabel("Edit")
                .accessibilityIdentifier("workoutDetail.edit")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save as Template", systemImage: "doc.on.doc") {
                    isTemplatePresented = true
                }
                .accessibilityLabel("Save as Template")
                .accessibilityIdentifier("workoutDetail.saveTemplate")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Delete", systemImage: "trash", role: .destructive) { isDeleteConfirming = true }
                    .accessibilityLabel("Delete")
                    .accessibilityIdentifier("workoutDetail.delete")
                    // On the button so the popover's arrow points at it.
                    .confirmationDialog(
                        "Delete workout?",
                        isPresented: $isDeleteConfirming,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Workout", role: .destructive, action: delete)
                            .accessibilityIdentifier("workoutDetail.delete.confirm")
                    } message: {
                        Text("\"\(detail.name)\" and every set in it will be deleted. This cannot be undone.")
                    }
            }
        }
        .sheet(isPresented: $isTemplatePresented) {
            if let workout {
                SaveTemplateSheet(workout: workout) { savedTemplates += 1 }
                    .presentationPlacement(.center)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.detail")
    }

    private func delete() {
        guard let workout else { return }
        context.delete(workout)
        do {
            try context.save()
            isDeleted = true
            detail = nil
            dismiss()
        } catch {
            context.rollback()
            deleteFailed = true
        }
    }
}

/// What the detail is derived from: changes when a finished workout is added, removed or edited, or a setting that
/// changes the numbers does, so the detail is recomputed then and not on every body evaluation.
private struct Inputs: Hashable {
    let ids: [UUID]
    let newestEdit: Date?
    let unit: WeightUnit?
    let formula: E1RMFormula?

    init(_ workouts: [Workout], unit: WeightUnit?, formula: E1RMFormula?) {
        ids = workouts.map(\.id)
        newestEdit = workouts.map(\.updatedAt).max()
        self.unit = unit
        self.formula = formula
    }
}

// MARK: - Header

/// Date, the three numbers and the note.
private struct DetailHeader: View {
    let detail: WorkoutDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(detail.dateText)
                .font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { stats }
                VStack(alignment: .leading, spacing: 8) { stats }
            }
            if !detail.note.isEmpty {
                Text(detail.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .dashboardCardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.headerAccessibilityLabel)
        .accessibilityIdentifier("workoutDetail.header")
    }

    @ViewBuilder
    private var stats: some View {
        stat("Duration", detail.durationText)
        stat("Volume", detail.volumeText)
        if detail.prCount > 0 {
            VStack(alignment: .leading, spacing: 2) {
                Text("Records")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(HistoryList.prText(count: detail.prCount), systemImage: "trophy.fill")
                    .font(.headline)
                    .foregroundStyle(.tint)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
    }
}

// MARK: - Exercise block

/// One exercise: superset bar, the `Exercise | Best Set` row, its completed sets and its record lines. One
/// accessibility element with a sentence label.
private struct ExerciseBlockView: View {
    let block: WorkoutDetail.ExerciseBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let number = block.supersetNumber {
                Text("Superset \(number)")
                    .font(.caption.bold())
                    .foregroundStyle(Color.superset(number))
            }
            titleRow
            if !block.note.isEmpty {
                Text(block.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
            ForEach(block.sets) { line in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(line.label)
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(line.kind.color)
                        .frame(minWidth: 28, alignment: .leading)
                    Text(line.text)
                        .font(.body.monospacedDigit())
                    Spacer(minLength: 0)
                    if line.isPR {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(.tint)
                    }
                }
            }
            if !block.prLines.isEmpty {
                Divider()
                ForEach(block.prLines, id: \.self) { text in
                    Label(text, systemImage: "trophy")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, block.supersetNumber == nil ? 0 : 8)
        .dashboardCardStyle()
        .overlay(alignment: .leading) {
            if let number = block.supersetNumber {
                Capsule()
                    .fill(Color.superset(number))
                    .frame(width: 4)
                    .padding(.vertical, 8)
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(block.accessibilityLabel)
        .accessibilityIdentifier("workoutDetail.exercise.\(block.id.uuidString)")
    }

    /// `Bench Press    Best Set 100 kg × 5`; stacks when the text is large.
    private var titleRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                name
                Spacer(minLength: 8)
                best
            }
            VStack(alignment: .leading, spacing: 2) {
                name
                best
            }
        }
    }

    private var name: some View {
        HStack(spacing: 6) {
            Text(block.name)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if !block.prLines.isEmpty {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.tint)
            }
        }
    }

    @ViewBuilder
    private var best: some View {
        if !block.bestSetText.isEmpty {
            VStack(alignment: .trailing, spacing: 0) {
                Text("Best Set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(block.bestSetText)
                    .font(.subheadline.monospacedDigit())
            }
        }
    }
}

// MARK: - Save as Template

/// Picks a folder (or none) and saves the workout's completed sets as a template. With no folders yet it offers to make
/// one called `Templates`. Success closes the sheet; a presenter may pass `saved` to play the success haptic.
struct SaveTemplateSheet: View {
    let workout: Workout
    let saved: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TemplateFolder.position) private var folders: [TemplateFolder]

    private enum Choice: Hashable {
        case none
        case folder(UUID)
        case new
    }

    @State private var choice: Choice?
    @State private var name: String
    @State private var failed = false

    init(workout: Workout, saved: @escaping () -> Void = {}) {
        self.workout = workout
        self.saved = saved
        _name = State(initialValue: workout.name)
    }

    /// The tick starts on the first folder, or on the new `Templates` folder when there is none.
    private var selection: Choice {
        choice ?? (folders.first.map { .folder($0.id) } ?? .new)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Template name", text: $name)
                        .accessibilityIdentifier("workoutDetail.saveTemplate.name")
                }
                Section("Folder") {
                    ForEach(folders) { folder in
                        row(folder.name, .folder(folder.id))
                            .accessibilityIdentifier("workoutDetail.saveTemplate.folder.\(folder.id.uuidString)")
                    }
                    if folders.isEmpty {
                        row("New folder \"Templates\"", .new)
                            .accessibilityIdentifier("workoutDetail.saveTemplate.folder.new")
                    }
                    row("No Folder", .none)
                        .accessibilityIdentifier("workoutDetail.saveTemplate.folder.none")
                }
            }
            .navigationTitle("Save as Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("workoutDetail.saveTemplate.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Template", systemImage: "checkmark", action: save)
                        .accessibilityLabel("Save Template")
                        .accessibilityIdentifier("workoutDetail.saveTemplate.confirm")
                }
            }
            .alert("Could not save the template.", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            }
        }
        .accessibilityIdentifier("workoutDetail.saveTemplate.sheet")
    }

    private func row(_ title: String, _ value: Choice) -> some View {
        Button {
            choice = value
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if selection == value {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }

    private func save() {
        let destination: TemplateDestination =
            switch selection {
            case .none: .none
            case .new: .newFolder(named: "Templates")
            case .folder(let id): folders.first { $0.id == id }.map { .folder($0) } ?? .none
            }
        do {
            try WorkoutDetail.saveAsTemplate(workout, named: name, to: destination, in: context)
            saved()
            dismiss()
        } catch {
            failed = true
        }
    }
}

// MARK: - Gallery and previews

#if DEBUG
    /// The detail of the newest sample workout, for the gallery (`-preview WorkoutDetail`) and the previews.
    struct WorkoutDetailDemo: View {
        @Query(
            filter: #Predicate<Workout> { $0.finishedAt != nil },
            sort: \Workout.startedAt,
            order: .reverse
        ) private var finished: [Workout]
        @State private var settings = SettingsStore()

        var body: some View {
            NavigationStack {
                if let first = finished.first {
                    WorkoutDetailView(workoutID: first.id)
                } else {
                    ProgressView()
                }
            }
            .environment(settings)
            .accessibilityIdentifier("screen.workoutDetail")
        }
    }

    #Preview("Large") {
        PreviewGallery.host("WorkoutDetail")
            .dynamicTypeSize(.large)
    }

    #Preview("Accessibility 3") {
        PreviewGallery.host("WorkoutDetail")
            .dynamicTypeSize(.accessibility3)
    }
#endif
