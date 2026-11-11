//
//  HistoryView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The History tab (task 5.1): a `NavigationStack` in both widths, a `List` with a `Section` per month of finished
/// workouts (newest first), search over workout and exercise names with an All / PRs scope, and Delete behind a
/// confirmation. A row pushes the workout detail (5.5) with the zoom transition. The stack's path
/// is `AppNavigation.historyPath`, so folding the Duo keeps it.
struct HistoryView: View {
    @Binding var path: [HistoryRoute]

    @Environment(ExerciseStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(StoreGeneration.self) private var generation: StoreGeneration?
    @Environment(SaveErrors.self) private var saveErrors: SaveErrors?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Optional so previews without the services still build; nil behaves like "no Health here".
    @Environment(HealthEnrichmentService.self) private var health: HealthEnrichmentService?
    @Query(
        filter: Workout.finishedPredicate,
        sort: \Workout.startedAt,
        order: .reverse
    ) private var finished: [Workout]
    // Read here only so a unit or formula change in Settings recomputes the rows.
    @AppStorage(SettingsKey.defaultUnit.rawValue) private var unitRaw = ""
    @AppStorage(SettingsKey.e1rmFormula.rawValue) private var formulaRaw = ""

    @State private var entries: [HistoryEntry] = []
    @State private var recentPRs: [RecentPR] = []
    /// False until the first summary lands; the dashboard cards that depend on it are placeholders until then.
    @State private var hasLoadedSummary = false
    @State private var query = ""
    @State private var scope: HistoryScope = .all
    /// Whether the search field is up. Dismissing it resets `scope`: the scope bar goes with the search, so a PRs scope
    /// left behind would filter the list and hide the dashboard with no control on screen to undo it.
    @State private var isSearchPresented = false
    /// The last summary read failed and no earlier one is on screen; the list is replaced by an error with Retry.
    @State private var loadFailed = false
    /// Bumped by Retry so the load task restarts.
    @State private var loadAttempt = 0
    @State private var pendingDelete: HistoryEntry?
    /// The workout whose delete just failed, and why; the alert's Retry deletes it again.
    @State private var deleteFailure: DeleteFailure?
    @State private var isCalendarPresented = false
    @State private var pendingOpen: UUID?
    @State private var templateSource: Workout?
    @State private var savedTemplates = 0
    /// The row whose past-workout editor is up (a full-screen cover).
    @State private var editing: PastEditorTarget?
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("History")
                // Same bar title as the Workout tab, so the tabs look alike on the open display.
                .toolbarTitleDisplayMode(.inlineLarge)
                .resumeControl()
                .settingsControl()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Calendar", systemImage: "calendar") { isCalendarPresented = true }
                            .accessibilityLabel("Calendar")
                            .accessibilityIdentifier("history.calendar")
                    }
                }
                .sheet(isPresented: $isCalendarPresented, onDismiss: openPending) {
                    CalendarSheet(entries: entries) { id in
                        pendingOpen = id
                        isCalendarPresented = false
                    }
                    .presentationPlacement(.center)
                }
                .sheet(item: $templateSource) { workout in
                    SaveTemplateSheet(workout: workout) { savedTemplates += 1 }
                        .presentationPlacement(.center)
                }
                .sensoryFeedback(.success, trigger: savedTemplates)
                .searchable(text: $query, isPresented: $isSearchPresented, prompt: "Search workouts")
                .onChange(of: isSearchPresented) { _, isPresented in
                    if !isPresented { scope = .all }
                }
                .searchScopes($scope, activation: .onSearchPresentation) {
                    ForEach(HistoryScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .navigationDestination(for: HistoryRoute.self) { route in
                    destination(route)
                }
                .pastWorkoutEditorCover($editing)
        }
        .task(
            id: Inputs(
                finished,
                generation: generation?.value ?? 0,
                unit: unitRaw,
                formula: formulaRaw,
                weightTypes: store.weightTypes,
                attempt: loadAttempt
            )
        ) {
            await refreshSummary()
        }
        .accessibilityIdentifier("screen.history")
    }

    /// Folds the history on a `WorkoutStatsReader` (its own context, off the main thread) and publishes the rows and the
    /// Recent PRs card here. What is shown stays until the new summary arrives, so a refresh never blanks the list.
    private func refreshSummary() async {
        await SlowLoads.delay()
        // The reader's context reads the store: flush edits the main context has not saved yet.
        context.saveIfChanged(reportingTo: saveErrors)
        let options = RecordsOptions(formula: settings.e1rmFormula, displayUnit: settings.defaultUnit)
        let summary =
            FailLoads.consumeHistory()
            ? nil
            : try? await WorkoutStatsReader.loadHistorySummary(
                in: context.container,
                weightTypes: store.weightTypes,
                options: options,
                // The most any layout lists; the compact cards slice it down.
                limit: DashboardCards.regularRecentPRLimit
            )
        guard !Task.isCancelled else { return }
        defer { hasLoadedSummary = true }
        guard let summary else {
            // Keep rows already on screen; with none, say the read failed instead of showing a bare dashboard.
            loadFailed = true
            return
        }
        loadFailed = false
        entries = summary.entries
        recentPRs = summary.recentPRs
    }

    // MARK: List

    @ViewBuilder
    private var content: some View {
        if finished.isEmpty {
            ContentUnavailableView(
                "No Workouts Yet",
                systemImage: "clock.arrow.circlepath",
                description: Text("Finish one from the Workout tab and it shows up here.")
            )
            .accessibilityIdentifier("history.empty")
        } else if loadFailed && entries.isEmpty {
            ContentUnavailableView {
                Label("Could Not Load History", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Your workouts could not be read. Nothing is lost.")
            } actions: {
                Button("Retry") {
                    loadFailed = false
                    hasLoadedSummary = false
                    loadAttempt += 1
                }
                .accessibilityIdentifier("history.loadFailed.retry")
            }
            .accessibilityIdentifier("history.loadFailed")
        } else {
            let sections = HistoryList.sections(HistoryList.filter(entries, query: query, scope: scope))
            // The list filter ignores surrounding whitespace, so a whitespace-only search keeps the dashboard.
            let isSearching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // Read from the models here, not from the cached entries: Fitness data lands after the workout was saved and
            // does not touch `updatedAt`, so the rows and the week's total follow the model.
            let activeKcal = activeKcalByWorkout
            let weekKcal = HistoryDashboard.weekActiveCalories(workouts: finished)
            let weekBpm = HistoryDashboard.weekAverageHeartRate(workouts: finished)
            let heartRates = avgHeartRateByWorkout
            List {
                if !isSearching && scope == .all {
                    Section {
                        if horizontalSizeClass == .regular {
                            // One row, two columns, the gutter on the fold when half open (`DashboardColumns`).
                            DashboardColumns(
                                entries: entries,
                                recentPRs: recentPRs,
                                weekActiveKcal: weekKcal,
                                weekAverageBpm: weekBpm,
                                isLoaded: hasLoadedSummary,
                                chart: { WeeklyGoalSection(starts: finished.map(\.startedAt), entries: entries) }
                            ) { path.append(.workout($0)) }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        } else {
                            // One row, so the chart and the cards under it share the grid's gap (separate list rows
                            // would add the row insets between them).
                            VStack(spacing: Metrics.dashboardSpacing) {
                                dashboard(.hero, weekKcal: weekKcal, weekBpm: weekBpm)
                                WeeklyGoalSection(starts: finished.map(\.startedAt), entries: entries)
                                dashboard(.rest, weekKcal: weekKcal, weekBpm: weekBpm)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                ForEach(sections) { section in
                    Section(section.title) {
                        if horizontalSizeClass == .regular {
                            // One list row per month holding a grid whose gutter is the fold, so no session straddles it.
                            // A `List` row is full width and `swipeActions` are per row, so the actions live in each
                            // card's context menu here (and as VoiceOver actions).
                            EvenColumnGrid(minimum: 280) {
                                ForEach(section.entries) { entry in
                                    card(entry, activeKcal: activeKcal[entry.id], avgBpm: heartRates[entry.id])
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(section.entries) { entry in
                                row(entry, activeKcal: activeKcal[entry.id], avgBpm: heartRates[entry.id])
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .fitnessRefresh(health, context: context)
            .overlay {
                if sections.isEmpty && !entries.isEmpty {
                    if !isSearching {
                        ContentUnavailableView(
                            "No PRs Yet",
                            systemImage: "trophy",
                            description: Text("Workouts that set a personal record show up here.")
                        )
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            // An alert, not a dialog: it is raised from a swipe action or a context menu, both gone by then, so a
            // popover's arrow would have nothing to point at.
            .alert(
                "Delete workout?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { entry in
                Button("Delete Workout", role: .destructive) { delete(entry) }
                    .accessibilityIdentifier("history.delete.confirm")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("history.delete.cancel")
            } message: { entry in
                Text("\"\(entry.name)\" and every set in it will be deleted. This cannot be undone.")
            }
            .alert(
                "Could Not Delete Workout",
                isPresented: Binding(get: { deleteFailure != nil }, set: { if !$0 { deleteFailure = nil } }),
                presenting: deleteFailure
            ) { failure in
                Button("Retry") { delete(failure.entry) }
                    .accessibilityIdentifier("history.delete.retry")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("history.delete.failed.cancel")
            } message: { failure in
                Text(failure.message)
            }
        }
    }

    /// Active calories from Apple Fitness per workout, for the workouts that have them.
    private var activeKcalByWorkout: [UUID: Double] {
        finished.reduce(into: [:]) { result, workout in
            if let kcal = workout.activeEnergyKcal { result[workout.id] = kcal }
        }
    }

    /// Average heart rate from Apple Fitness per workout, for the workouts that have one.
    private var avgHeartRateByWorkout: [UUID: Double] {
        finished.reduce(into: [:]) { result, workout in
            if let bpm = workout.avgHeartRate { result[workout.id] = bpm }
        }
    }

    private func dashboard(_ part: DashboardCards.Part, weekKcal: Double?, weekBpm: Double?) -> some View {
        DashboardSection(
            entries: entries,
            recentPRs: recentPRs,
            weekActiveKcal: weekKcal,
            weekAverageBpm: weekBpm,
            isLoaded: hasLoadedSummary,
            part: part
        ) {
            path.append(.workout($0))
        }
    }

    private func row(_ entry: HistoryEntry, activeKcal: Double?, avgBpm: Double?) -> some View {
        NavigationLink(value: HistoryRoute.workout(entry.id)) {
            HistoryRow(entry: entry, activeKcal: activeKcal, avgBpm: avgBpm)
        }
        .matchedTransitionSource(id: entry.id, in: zoom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            HistoryList.accessibilityLabel(for: entry, activeKcal: activeKcal)
                + (avgBpm.map { ", \(HistoryDashboard.heartRateSpoken($0))" } ?? "")
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("history.row.\(entry.id.uuidString)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            deleteButton(entry)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            editButton(entry)
            saveTemplateButton(entry)
        }
        .contextMenu {
            editButton(entry)
            saveTemplateButton(entry)
            Divider()
            deleteButton(entry)
        }
    }

    /// A session as a card in the regular-width grid: the same content as `row`, a chevron at the card's own trailing edge
    /// (inside one column, so never across the fold), and Edit / Save as Template / Delete in the context menu and as
    /// accessibility actions in place of the swipe.
    private func card(_ entry: HistoryEntry, activeKcal: Double?, avgBpm: Double?) -> some View {
        Button {
            path.append(.workout(entry.id))
        } label: {
            HStack(spacing: 8) {
                HistoryRow(entry: entry, activeKcal: activeKcal, avgBpm: avgBpm)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardBackground()
            .cardContentShape()
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: entry.id, in: zoom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            HistoryList.accessibilityLabel(for: entry, activeKcal: activeKcal)
                + (avgBpm.map { ", \(HistoryDashboard.heartRateSpoken($0))" } ?? "")
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("history.row.\(entry.id.uuidString)")
        .accessibilityAction(named: "Edit") { editing = PastEditorTarget(id: entry.id) }
        .accessibilityAction(named: "Save as Template") {
            templateSource = finished.first { $0.id == entry.id }
        }
        .accessibilityAction(named: "Delete") { pendingDelete = entry }
        .contextMenu {
            editButton(entry)
            saveTemplateButton(entry)
            Divider()
            deleteButton(entry)
        }
    }

    private func editButton(_ entry: HistoryEntry) -> some View {
        Button {
            editing = PastEditorTarget(id: entry.id)
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .accessibilityLabel("Edit")
        .accessibilityIdentifier("history.edit")
    }

    private func saveTemplateButton(_ entry: HistoryEntry) -> some View {
        Button {
            templateSource = finished.first { $0.id == entry.id }
        } label: {
            Label("Save as Template", systemImage: "doc.on.doc")
        }
        .accessibilityLabel("Save as Template")
        .accessibilityIdentifier("history.saveTemplate")
    }

    private func deleteButton(_ entry: HistoryEntry) -> some View {
        Button(role: .destructive) {
            pendingDelete = entry
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityLabel("Delete")
        .accessibilityIdentifier("history.delete")
    }

    private func delete(_ entry: HistoryEntry) {
        pendingDelete = nil
        guard let workout = finished.first(where: { $0.id == entry.id }) else { return }
        context.delete(workout)
        do {
            try context.save()
            generation?.bump()
            entries.removeAll { $0.id == entry.id }
        } catch {
            context.rollback()
            deleteFailure = DeleteFailure(entry: entry, message: DeleteFailure.message(for: error))
        }
    }

    /// Pushes the workout picked in the Calendar once the sheet has gone.
    private func openPending() {
        guard let id = pendingOpen else { return }
        pendingOpen = nil
        path.append(.workout(id))
    }

    // MARK: Destination

    @ViewBuilder
    private func destination(_ route: HistoryRoute) -> some View {
        switch route {
        case .workout(let id):
            WorkoutDetailView(workoutID: id)
                .navigationTransition(.zoom(sourceID: id, in: zoom))
        }
    }
}

/// One History row in the style of a Fitness session: the name and short date, the volume in the accent colour with the
/// duration beside it and the PR count (gold) at the trailing edge, and a neutral line of the Apple Fitness values when
/// there are any.
struct HistoryRow: View {
    let entry: HistoryEntry
    var activeKcal: Double?
    var avgBpm: Double?

    private var volumeText: String { HistoryList.volumeText(entry.volume, unit: entry.unit) }
    private var durationText: String { HistoryList.durationText(seconds: entry.durationSeconds) }

    /// `266 kcal · 128 bpm`; empty without Health values.
    private var healthText: String {
        var parts: [String] = []
        if let activeKcal { parts.append(FitnessFormat.kcalText(activeKcal)) }
        if let avgBpm { parts.append(HistoryDashboard.heartRateText(avgBpm)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleLine
            metricsLine
            if !healthText.isEmpty {
                Text(healthText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameLabel: some View {
        Text(entry.name)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private var dateLabel: some View {
        Text(HistoryList.shortDateText(entry.startedAt))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    /// Name and date on one line; the date drops under the name when the two do not fit side by side.
    private var titleLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                nameLabel.lineLimit(1)
                Spacer(minLength: 8)
                dateLabel.lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                nameLabel
                dateLabel
            }
        }
    }

    private var volumeLabel: some View {
        MetricText(volumeText, style: .title3)
            .foregroundStyle(.tint)
    }

    private var durationLabel: some View {
        Text(durationText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    /// Volume, duration beside it and the PR count at the trailing edge; the duration and PRs wrap under the volume
    /// when the line does not fit.
    private var metricsLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !volumeText.isEmpty { volumeLabel.lineLimit(1) }
                durationLabel.lineLimit(1)
                Spacer(minLength: 8)
                prLabel
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !volumeText.isEmpty { volumeLabel }
                    durationLabel
                }
                prLabel
            }
        }
    }

    @ViewBuilder
    private var prLabel: some View {
        if entry.prCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "trophy.fill")
                Text("\(entry.prCount)")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.record)
        }
    }
}

/// Changes when a finished workout is added, removed or edited, or a setting or an exercise's weight type that changes
/// the numbers does, so the
/// rows are recomputed then and not per render.
private struct Inputs: Hashable {
    let ids: [UUID]
    let newestEdit: Date?
    /// `StoreGeneration`: an import can update an older workout without moving the ids or the newest stamp.
    let generation: Int
    let unit: String
    let formula: String
    /// A custom exercise's weight type edit changes its volume and PRs without touching any workout.
    let weightTypes: [UUID: WeightType]
    /// Retry after a failed read.
    let attempt: Int

    init(
        _ workouts: [Workout],
        generation: Int,
        unit: String,
        formula: String,
        weightTypes: [UUID: WeightType],
        attempt: Int
    ) {
        self.attempt = attempt
        ids = workouts.map(\.id)
        self.generation = generation
        newestEdit = workouts.map(\.updatedAt).max()
        self.unit = unit
        self.formula = formula
        self.weightTypes = weightTypes
    }
}

#if DEBUG
    /// Hosts `HistoryView` with its own path for the gallery and the previews.
    struct HistoryDemo: View {
        @State private var path: [HistoryRoute] = []
        @State private var settings = SettingsStore()

        var body: some View {
            HistoryView(path: $path)
                .environment(settings)
        }
    }

    #Preview("Large") {
        PreviewGallery.host("History")
            .dynamicTypeSize(.large)
    }

    #Preview("Accessibility 3") {
        PreviewGallery.host("History")
            .dynamicTypeSize(.accessibility3)
    }
#endif

/// Pull to refresh on the History list forces an Apple Fitness lookup now, past the 15-minute throttle. With Health off or
/// unavailable there is nothing to refresh, so no refresh control is attached and the list does not pull at all. (SwiftUI
/// has no way to switch `refreshable` off in place, since `EnvironmentValues.refresh` is read-only, so toggling Health
/// rebuilds the list once, which only happens from the Settings sheet.)
private struct FitnessRefresh: ViewModifier {
    let health: HealthEnrichmentService?
    let context: ModelContext

    @ViewBuilder
    func body(content: Content) -> some View {
        if let health, health.isActive {
            content.refreshable { await health.refreshNow(context: context) }
        } else {
            content
        }
    }
}

extension View {
    fileprivate func fitnessRefresh(_ health: HealthEnrichmentService?, context: ModelContext) -> some View {
        modifier(FitnessRefresh(health: health, context: context))
    }
}
