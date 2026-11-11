//
//  WorkoutDetailView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The workout detail (task 5.5), pushed from a History row with the zoom transition: the date, duration, volume and
/// PR count, the workout note, then one block per exercise with its completed sets (a trophy on the sets that set a
/// record) and a line per record. The bar has Edit (presents the past-workout editor, 5.6), Save as Template and Delete. Everything shown is derived on read by
/// `WorkoutDetail` in the kit.
struct WorkoutDetailView: View {
    let workoutID: UUID

    @Environment(ExerciseStore.self) private var store
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(StoreGeneration.self) private var generation: StoreGeneration?
    @Environment(SaveErrors.self) private var saveErrors: SaveErrors?
    /// This workout alone (zero or one row): Edit, Save as Template and Delete need no more, and it keys the detail.
    @Query private var current: [Workout]
    /// The newest edit among finished workouts: with the store generation it tells the detail that the history its
    /// records are judged against changed (the whole set is fetched once per change in the task, not observed).
    @Query(Workout.newestFinishedEdit) private var newest: [Workout]

    /// The past-workout editor, a full-screen cover over this screen (Save and Cancel both return here).
    @State private var editing: PastEditorTarget?
    @State private var isTemplatePresented = false
    @State private var isDeleteConfirming = false
    /// Why the last delete failed; non-nil shows the alert, whose Retry deletes again.
    @State private var deleteFailureMessage: String?
    @State private var isDeleted = false
    @State private var savedTemplates = 0
    /// Derived in `.task(id:)` when the history or a setting changes, never in `body`.
    @State private var detail: WorkoutDetail?
    @State private var isLoaded = false
    /// The history could not be read and there is no earlier detail to keep showing.
    @State private var loadFailed = false

    init(workoutID: UUID) {
        self.workoutID = workoutID
        _current = Query(Workout.finished(id: workoutID))
    }

    var body: some View {
        ZStack {
            if let detail {
                content(detail)
            } else if loadFailed {
                ContentUnavailableView(
                    "Could Not Load Workout",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The workout history could not be read.")
                )
                .accessibilityIdentifier("history.detail.loadFailed")
            } else if isLoaded && !isDeleted {
                ContentUnavailableView(
                    "Workout Not Found",
                    systemImage: "questionmark.folder",
                    description: Text("That workout does not exist.")
                )
                .accessibilityIdentifier("history.detail.missing")
            } else if !isLoaded {
                DelayedLoadingIndicator(label: "Loading workout")
                    .accessibilityIdentifier("history.detail.loading")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") { editing = PastEditorTarget(id: workoutID) }
                    .accessibilityLabel("Edit")
                    .accessibilityIdentifier("workoutDetail.edit")
                    .disabled(workout == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save as Template", systemImage: "doc.on.doc") {
                    isTemplatePresented = true
                }
                .accessibilityLabel("Save as Template")
                .accessibilityIdentifier("workoutDetail.saveTemplate")
                .disabled(workout == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Delete", systemImage: "trash", role: .destructive) { isDeleteConfirming = true }
                    .accessibilityLabel("Delete")
                    .accessibilityIdentifier("workoutDetail.delete")
                    .disabled(workout == nil)
                    // On the button so the popover's arrow points at it.
                    .confirmationDialog(
                        "Delete workout?",
                        isPresented: $isDeleteConfirming,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Workout", role: .destructive, action: delete)
                            .accessibilityIdentifier("workoutDetail.delete.confirm")
                    } message: {
                        Text("\"\(title)\" and every set in it will be deleted. This cannot be undone.")
                    }
            }
        }
        .pastWorkoutEditorCover($editing)
        .sheet(isPresented: $isTemplatePresented) {
            if let workout {
                SaveTemplateSheet(workout: workout) { savedTemplates += 1 }
                    .presentationPlacement(.center)
            }
        }
        .task(id: inputs) {
            if isDeleted {
                detail = nil
                isLoaded = true
            } else {
                await refreshDetail()
            }
        }
        .sensoryFeedback(.success, trigger: savedTemplates)
        .alert(
            "Could Not Delete Workout",
            isPresented: Binding(
                get: { deleteFailureMessage != nil },
                set: { if !$0 { deleteFailureMessage = nil } }
            )
        ) {
            Button("Retry", action: delete)
                .accessibilityIdentifier("workoutDetail.delete.retry")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("workoutDetail.delete.failed.cancel")
        } message: {
            Text(deleteFailureMessage ?? "")
        }
    }

    private var inputs: WorkoutDetailInputs {
        WorkoutDetailInputs(
            workout: current.first,
            newestEdit: newest.first?.updatedAt,
            generation: generation?.value ?? 0,
            unit: settings?.defaultUnit,
            formula: settings?.e1rmFormula,
            weightTypes: store.weightTypes
        )
    }

    /// Derives the detail on a `WorkoutStatsReader` (its own context, off the main thread): records are judged against the
    /// whole history, which is too much to walk here. What is shown stays until the new detail arrives; a failed read
    /// keeps it, or shows the load-failed state when there is nothing to keep.
    private func refreshDetail() async {
        await SlowLoads.delay()
        // The reader's context reads the store: flush edits the main context has not saved yet.
        context.saveIfChanged(reportingTo: saveErrors)
        let options = RecordsOptions(
            formula: settings?.e1rmFormula ?? SettingsStore.e1rmFormulaDefault,
            displayUnit: settings?.defaultUnit ?? SettingsStore.defaultUnitDefault
        )
        // `try?` would flatten "no such workout" (nil, shown as Not Found) into a failed read; keep them apart.
        do {
            let loaded = try await WorkoutStatsReader.loadWorkoutDetail(
                in: context.container,
                id: workoutID,
                weightTypes: store.weightTypes,
                options: options
            )
            guard !Task.isCancelled else { return }
            detail = loaded
            isLoaded = true
            loadFailed = false
        } catch {
            // Keep a detail already on screen; with none, say the read failed instead of spinning forever.
            if detail == nil, !Task.isCancelled { loadFailed = true }
        }
    }

    private var workout: Workout? { current.first }

    /// The bar's title, from the model the `@Query` already holds on the first frame (the derived `detail` arrives later
    /// and is only a fallback), so the push never shows an untitled bar.
    private var title: String { workout?.name ?? detail?.name ?? "" }

    // MARK: Content

    private func content(_ detail: WorkoutDetail) -> some View {
        ScrollView {
            // Read from the model here, not from `detail`: Health data lands after the workout was saved and does
            // not touch `updatedAt`, so the stats and the chart appear (and go) as the model changes.
            let health = workout?.healthSummary
            if horizontalSizeClass == .regular {
                // Two columns that keep off the fold (`FoldColumns`): the header and chart on the left, then the
                // exercise blocks in order, split where the two columns come out closest in height.
                let split = Self.splitIndex(
                    blocks: detail.exercises,
                    leadingWeight: Self.headerWeight + (hasChart(health) ? Self.chartWeight : 0)
                )
                FoldColumns {
                    VStack(alignment: .leading, spacing: 16) {
                        headerAndChart(detail, health: health)
                        ForEach(detail.exercises.prefix(split)) { block in
                            ExerciseBlockView(block: block)
                        }
                        emptyNote(detail)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(detail.exercises.dropFirst(split)) { block in
                            ExerciseBlockView(block: block)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    headerAndChart(detail, health: health)
                    ForEach(detail.exercises) { block in
                        ExerciseBlockView(block: block)
                    }
                    emptyNote(detail)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.detail")
    }

    @ViewBuilder
    private func headerAndChart(_ detail: WorkoutDetail, health: HealthWorkoutSummary?) -> some View {
        DetailHeader(detail: detail, health: health)
        if let workout, let health, HeartRateChart.canShow(series: health.heartRateSeries) {
            HeartRateChart(
                series: health.heartRateSeries,
                timeline: SetTimeline.make(workout: workout),
                average: health.avgHeartRate,
                maximum: health.maxHeartRate,
                zones: health.zones
            )
            .dashboardCardStyle()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workoutDetail.heartRate")
        }
    }

    @ViewBuilder
    private func emptyNote(_ detail: WorkoutDetail) -> some View {
        if detail.exercises.isEmpty {
            Text("No completed sets in this workout.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func hasChart(_ health: HealthWorkoutSummary?) -> Bool {
        workout != nil && health.map { HeartRateChart.canShow(series: $0.heartRateSeries) } == true
    }

    // MARK: Two-column split

    /// Rough heights in set-row units, only to balance the columns (the real heights are not known before layout).
    static let headerWeight = 5
    static let chartWeight = 7

    /// How many leading blocks go in the left column (under the header and chart, `leadingWeight`): the count that makes
    /// the two columns' estimated heights closest. Blocks keep their order, so the right column continues the left.
    static func splitIndex(blocks: [WorkoutDetail.ExerciseBlock], leadingWeight: Int) -> Int {
        let weights = blocks.map { 3 + $0.sets.count + $0.prLines.count + ($0.note.isEmpty ? 0 : 1) }
        let total = leadingWeight + weights.reduce(0, +)
        var left = leadingWeight
        var best = 0
        var bestGap = abs(total - 2 * left)
        for (index, weight) in weights.enumerated() {
            left += weight
            let gap = abs(total - 2 * left)
            if gap < bestGap {
                best = index + 1
                bestGap = gap
            }
        }
        return best
    }

    private func delete() {
        guard let workout else { return }
        context.delete(workout)
        do {
            try context.save()
            generation?.bump()
            isDeleted = true
            detail = nil
            dismiss()
        } catch {
            context.rollback()
            deleteFailureMessage = DeleteFailure.message(for: error)
        }
    }
}

/// What the detail is derived from: changes when a finished workout is added, removed or edited, or a setting that
/// changes the numbers does, so the detail is recomputed then and not on every body evaluation.
struct WorkoutDetailInputs: Hashable {
    /// The workout's own identity and stamp: nil once it is gone, a new stamp after an edit of it.
    let workoutID: UUID?
    let workoutEdit: Date?
    let newestEdit: Date?
    /// `StoreGeneration`: an import can update an older workout, or a delete remove one, without moving the newest stamp.
    let generation: Int
    let unit: WeightUnit?
    let formula: E1RMFormula?
    /// A custom exercise's weight type edit changes the volume, best set and PRs without touching any workout
    /// (the same signal `HistoryView` and `ExercisesView` reload on).
    let weightTypes: [UUID: WeightType]

    init(
        workout: Workout?,
        newestEdit: Date?,
        generation: Int,
        unit: WeightUnit?,
        formula: E1RMFormula?,
        weightTypes: [UUID: WeightType]
    ) {
        workoutID = workout?.id
        workoutEdit = workout?.updatedAt
        self.newestEdit = newestEdit
        self.generation = generation
        self.unit = unit
        self.formula = formula
        self.weightTypes = weightTypes
    }
}

// MARK: - Header

/// Date (with the weather, when Health had it), the stats and the note. The stats sit in fixed pairs, side by side:
/// Duration · Volume, Records · Effort, Active · Total, Avg HR · Max HR. Duration and volume are always there, Records
/// when there are any; the Health tiles only when the matched Health workout has the value. A pair with one tile shows
/// it in the first column, a pair with none is dropped, so the second column starts at one x in every row. At
/// accessibility text sizes every tile stacks in one column in the same order. Every tile is one caption line plus one
/// value line.
struct DetailHeader: View {
    let detail: WorkoutDetail
    let health: HealthWorkoutSummary?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Stat {
        let title: String
        let value: String
        var unit: String?
        /// A rating word set beside the value in plain secondary text ("Hard"), not as a unit.
        var rating: String?
        var symbol: String?
        var tint: Color = .primary
        var hierarchical = false
        /// The record count takes its tint; the other values stay primary.
        var tintsValue = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.dateText)
                    .font(.headline)
                if let health, health.weatherTemperatureCelsius != nil || health.weatherHumidityPercent != nil {
                    weatherRow(health)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            statsLayout
            if !detail.note.isEmpty {
                Text(detail.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .dashboardCardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.accessibilityLabel(health: health))
        .accessibilityIdentifier("workoutDetail.header")
    }

    @ViewBuilder
    private var statsLayout: some View {
        let pairs = statPairs
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(pairs.indices, id: \.self) { index in
                    ForEach([pairs[index].leading, pairs[index].trailing].compactMap { $0 }, id: \.title) { stat in
                        statView(stat)
                    }
                }
            }
        } else {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 12) {
                ForEach(pairs.indices, id: \.self) { index in
                    GridRow {
                        if let leading = pairs[index].leading {
                            statView(leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let trailing = pairs[index].trailing {
                            statView(trailing)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    /// The tiles in their fixed pairs; a pair with one tile has it leading, a pair with none is dropped.
    private var statPairs: [(leading: Stat?, trailing: Stat?)] {
        let records =
            detail.prCount > 0
            ? Stat(
                title: "Records",
                value: "\(detail.prCount)",
                symbol: "trophy.fill",
                tint: Color.record,
                tintsValue: true
            )
            : nil
        let effort = health?.effort.map { effort in
            Stat(
                title: effort.isEstimated ? "Est. Effort" : "Effort",
                value: "\(FitnessFormat.wholeScore(effort.score))",
                rating: effort.word,
                symbol: "gauge.with.dots.needle.67percent",
                tint: .purple,
                hierarchical: true
            )
        }
        let active = health?.activeEnergyKcal.map {
            Stat(
                title: "Active",
                value: FitnessFormat.wholeNumber($0),
                unit: "kcal",
                symbol: "flame.fill",
                tint: .orange
            )
        }
        let total = health?.totalEnergyKcal.map {
            Stat(title: "Total", value: FitnessFormat.wholeNumber($0), unit: "kcal", symbol: "flame", tint: .orange)
        }
        let average = health?.avgHeartRate.map {
            Stat(title: "Avg HR", value: FitnessFormat.wholeNumber($0), unit: "bpm", symbol: "heart.fill", tint: .red)
        }
        let maximum = health?.maxHeartRate.map {
            Stat(
                title: "Max HR",
                value: FitnessFormat.wholeNumber($0),
                unit: "bpm",
                symbol: "arrow.up.heart.fill",
                tint: .red
            )
        }
        let pairs: [(Stat?, Stat?)] = [
            (Stat(title: "Duration", value: detail.durationText), Stat(title: "Volume", value: detail.volumeText)),
            (records, effort),
            (active, total),
            (average, maximum),
        ]
        return pairs.compactMap { first, second in
            switch (first, second) {
            case (nil, nil): nil
            case (nil, let second?): (leading: second, trailing: nil)
            default: (leading: first, trailing: second)
            }
        }
    }

    private func statView(_ stat: Stat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let symbol = stat.symbol {
                    Image(systemName: symbol)
                        .symbolRenderingMode(stat.hierarchical ? .hierarchical : .monochrome)
                        .font(.subheadline)
                        .foregroundStyle(stat.tint)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    MetricText(stat.unit.map { "\(stat.value) \($0)" } ?? stat.value, style: .title2)
                        .foregroundStyle(stat.tintsValue ? stat.tint : Color.primary)
                    if let rating = stat.rating {
                        Text(rating)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Weather

    /// The temperature and humidity under the date; stacks when the text is large.
    private func weatherRow(_ health: HealthWorkoutSummary) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                weatherItems(health)
            }
            VStack(alignment: .leading, spacing: 2) {
                weatherItems(health)
            }
        }
    }

    @ViewBuilder
    private func weatherItems(_ health: HealthWorkoutSummary) -> some View {
        if let celsius = health.weatherTemperatureCelsius {
            Label(FitnessFormat.temperatureText(celsius: celsius), systemImage: "thermometer.medium")
        }
        if health.weatherTemperatureCelsius != nil, health.weatherHumidityPercent != nil {
            Text("\u{00B7}")
                .accessibilityHidden(true)
        }
        if let humidity = health.weatherHumidityPercent {
            Label(FitnessFormat.humidityText(percent: humidity), systemImage: "humidity")
        }
    }
}

// MARK: - Exercise block

/// One exercise: superset bar, the `Exercise | Best Set` row, its completed sets and its record lines. One
/// accessibility element with a sentence label.
private struct ExerciseBlockView: View {
    let block: WorkoutDetail.ExerciseBlock

    @ScaledMetric(relativeTo: .body) private var labelWidth = Metrics.setLabelWidth

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
                        .frame(width: labelWidth, alignment: .leading)
                    Text(line.text)
                        .font(.body.monospacedDigit())
                    Spacer(minLength: 0)
                    if line.isPR {
                        Image(systemName: "trophy.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.record)
                    }
                }
            }
            if !block.prLines.isEmpty {
                Divider()
                ForEach(block.prLines, id: \.self) { text in
                    Label {
                        Text(text)
                    } icon: {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(Color.record)
                    }
                    .font(.footnote)
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
                    .frame(width: Metrics.supersetBarWidth)
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
            // Side by side only when the name fits on one line; otherwise the next layout stacks them.
            HStack(alignment: .firstTextBaseline) {
                name.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                best(alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                name
                best(alignment: .leading)
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
                    .font(.subheadline)
                    .foregroundStyle(Color.record)
            }
        }
    }

    @ViewBuilder
    private func best(alignment: HorizontalAlignment) -> some View {
        if !block.bestSetText.isEmpty {
            VStack(alignment: alignment, spacing: 0) {
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
    @State private var failureMessage: String?

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
                CancelToolbarItem(id: "workoutDetail.saveTemplate.cancel") { dismiss() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Template", systemImage: "checkmark", action: save)
                        .accessibilityLabel("Save Template")
                        .accessibilityIdentifier("workoutDetail.saveTemplate.confirm")
                }
            }
            .alert(
                "Could Not Save Template",
                isPresented: Binding(get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } })
            ) {
                Button("Retry", action: save)
                    .accessibilityIdentifier("workoutDetail.saveTemplate.retry")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("workoutDetail.saveTemplate.failed.cancel")
            } message: {
                Text(failureMessage ?? "")
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
            failureMessage = "Could not save the template: \(error.localizedDescription). Nothing was changed."
        }
    }
}

// MARK: - Gallery and previews

#if DEBUG
    /// The detail of the newest sample workout, for the gallery (`-preview WorkoutDetail`) and the previews.
    struct WorkoutDetailDemo: View {
        @Query(
            filter: Workout.finishedPredicate,
            sort: \Workout.startedAt,
            order: .reverse
        ) private var finished: [Workout]
        @State private var settings = SettingsStore()

        var body: some View {
            NavigationStack {
                if let first = finished.first {
                    WorkoutDetailView(workoutID: first.id)
                        .task(id: first.id) { await enrich(first) }
                } else {
                    ProgressView().tint(.secondary)
                }
            }
            .environment(settings)
            .accessibilityIdentifier("screen.workoutDetail")
        }

        /// With `-healthFixture <name>` (as in `-preview WorkoutDetail -healthFixture full`) the sample workout is
        /// enriched from that fixture the way the app does it, so the Health stats and chart appear live. With
        /// `-healthReal` it reads the simulator's real Health store instead (after `-seedHealth` finishes, if passed):
        /// the real-store integration test's subject; the sample workout then takes the seeder's last-hour window.
        private func enrich(_ workout: Workout) async {
            if ProcessInfo.processInfo.arguments.contains("-healthReal") {
                await enrichFromRealStore(workout)
                return
            }
            guard let fixture = HealthFixture.requested() else { return }
            let summary = try? await HealthEnrichment(source: fixture.anyWorkoutSource)
                .enrich(workoutStart: workout.startedAt, workoutEnd: workout.finishedAt ?? workout.startedAt)
            workout.applyHealth(summary, checkedAt: .now)
        }

        private func enrichFromRealStore(_ workout: Workout) async {
            await HealthSeeder.seeding?.value
            let source = HealthKitSource()
            do { try await source.requestReadAuthorization() } catch { return }
            // The seed spans the last 50 minutes; read the last 60.
            let end = Date.now
            let summary = try? await HealthEnrichment(source: source)
                .enrich(workoutStart: end.addingTimeInterval(-60 * 60), workoutEnd: end)
            workout.applyHealth(summary, checkedAt: .now)
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

/// A centered spinner for a body whose load is still running. It appears after a short delay so a fast load never
/// flashes it; the screen's chrome is already on screen, this only fills the body.
private struct DelayedLoadingIndicator: View {
    let label: LocalizedStringKey
    @State private var isVisible = false

    var body: some View {
        ProgressView()
            .tint(.secondary)
            .controlSize(.large)
            .opacity(isVisible ? 1 : 0)
            .accessibilityLabel(label)
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                isVisible = true
            }
    }
}
