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
    @State private var query = ""
    @State private var scope: HistoryScope = .all
    @State private var pendingDelete: HistoryEntry?
    @State private var deleteFailed = false
    @State private var isCalendarPresented = false
    @State private var pendingOpen: UUID?
    @State private var templateSource: Workout?
    @State private var savedTemplates = 0
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
                .searchable(text: $query, prompt: "Search workouts")
                .searchScopes($scope, activation: .onSearchPresentation) {
                    ForEach(HistoryScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .navigationDestination(for: HistoryRoute.self) { route in
                    destination(route)
                }
        }
        .task(
            id: Inputs(
                finished,
                generation: generation?.value ?? 0,
                unit: unitRaw,
                formula: formulaRaw,
                weightTypes: store.weightTypes
            )
        ) {
            await refreshSummary()
        }
        .accessibilityIdentifier("screen.history")
    }

    /// Folds the history on a `WorkoutStatsReader` (its own context, off the main thread) and publishes the rows and the
    /// Recent PRs card here. What is shown stays until the new summary arrives, so a refresh never blanks the list.
    private func refreshSummary() async {
        // The reader's context reads the store: flush edits the main context has not saved yet.
        context.saveIfChanged(reportingTo: saveErrors)
        let options = RecordsOptions(formula: settings.e1rmFormula, displayUnit: settings.defaultUnit)
        let summary = try? await WorkoutStatsReader.loadHistorySummary(
            in: context.container,
            weightTypes: store.weightTypes,
            options: options
        )
        guard !Task.isCancelled, let summary else { return }
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
                                starts: finished.map(\.startedAt),
                                entries: entries,
                                recentPRs: recentPRs,
                                weekActiveKcal: weekKcal,
                                weekAverageBpm: weekBpm
                            ) { path.append(.workout($0)) }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        } else {
                            WeeklyGoalSection(starts: finished.map(\.startedAt))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            DashboardSection(
                                entries: entries,
                                recentPRs: recentPRs,
                                weekActiveKcal: weekKcal,
                                weekAverageBpm: weekBpm
                            ) {
                                path.append(.workout($0))
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.entries) { entry in
                            row(entry, activeKcal: activeKcal[entry.id], avgBpm: heartRates[entry.id])
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
            .alert("Could not delete the workout.", isPresented: $deleteFailed) {
                Button("OK", role: .cancel) {}
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

    private func editButton(_ entry: HistoryEntry) -> some View {
        Button {
            path.append(.editWorkout(entry.id))
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
            deleteFailed = true
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
        case .editWorkout(let id):
            PastWorkoutEditor(workoutID: id)
        }
    }
}

/// One History row: name, date, then duration, volume and (from Apple Fitness) active calories and average heart rate,
/// and the PR count with a trophy.
private struct HistoryRow: View {
    let entry: HistoryEntry
    var activeKcal: Double?
    var avgBpm: Double?

    /// `45min · 15,421 lb · 266 kcal · 128 bpm`.
    private var statsText: String {
        var parts = [
            HistoryList.durationText(seconds: entry.durationSeconds),
            HistoryList.volumeText(entry.volume, unit: entry.unit),
        ]
        if let activeKcal { parts.append(FitnessFormat.kcalText(activeKcal)) }
        if let avgBpm { parts.append(HistoryDashboard.heartRateText(avgBpm)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.name)
                .font(.headline)
            Text(HistoryList.dateText(entry.startedAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(statsText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if entry.prCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                    Text(HistoryList.prText(count: entry.prCount))
                }
                .font(.subheadline)
                .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    init(_ workouts: [Workout], generation: Int, unit: String, formula: String, weightTypes: [UUID: WeightType]) {
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
