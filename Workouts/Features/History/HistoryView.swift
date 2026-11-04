//
//  HistoryView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The History tab (task 5.1): a `NavigationStack` in both widths, a `List` with a `Section` per month of finished
/// workouts (newest first), search over workout and exercise names with an All / PRs scope, and Delete behind a
/// confirmation. A row pushes the workout detail (a placeholder until 5.5) with the zoom transition. The stack's path
/// is `AppNavigation.historyPath`, so folding the Duo keeps it.
struct HistoryView: View {
    @Binding var path: [HistoryRoute]

    @Environment(ExerciseStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<Workout> { $0.finishedAt != nil },
        sort: \Workout.startedAt,
        order: .reverse
    ) private var finished: [Workout]
    // Read here only so a unit or formula change in Settings recomputes the rows.
    @AppStorage(SettingsKey.defaultUnit.rawValue) private var unitRaw = ""
    @AppStorage(SettingsKey.e1rmFormula.rawValue) private var formulaRaw = ""

    @State private var entries: [HistoryEntry] = []
    @State private var query = ""
    @State private var scope: HistoryScope = .all
    @State private var pendingDelete: HistoryEntry?
    @State private var deleteFailed = false
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("History")
                .resumeControl()
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
        .task(id: Inputs(finished, unit: unitRaw, formula: formulaRaw)) {
            let settings = SettingsStore()
            entries = HistoryList.entries(
                from: finished,
                weightType: { store.exercise(id: $0)?.weightType },
                options: RecordsOptions(formula: settings.e1rmFormula, displayUnit: settings.defaultUnit)
            )
        }
        .accessibilityIdentifier("screen.history")
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
            List {
                if query.isEmpty && scope == .all {
                    Section {
                        WeeklyGoalSection(starts: finished.map(\.startedAt))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.entries) { entry in
                            row(entry)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if sections.isEmpty && !entries.isEmpty {
                    if query.isEmpty {
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
            .confirmationDialog(
                "Delete workout?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { entry in
                Button("Delete Workout", role: .destructive) { delete(entry) }
                    .accessibilityIdentifier("history.delete.confirm")
            } message: { entry in
                Text("\"\(entry.name)\" and every set in it will be deleted. This cannot be undone.")
            }
            .alert("Could not delete the workout.", isPresented: $deleteFailed) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        NavigationLink(value: HistoryRoute.workout(entry.id)) {
            HistoryRow(entry: entry)
        }
        .matchedTransitionSource(id: entry.id, in: zoom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistoryList.accessibilityLabel(for: entry))
        .accessibilityIdentifier("history.row.\(entry.id.uuidString)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            deleteButton(entry)
        }
        .contextMenu {
            deleteButton(entry)
        }
    }

    private func deleteButton(_ entry: HistoryEntry) -> some View {
        Button(role: .destructive) {
            pendingDelete = entry
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityIdentifier("history.delete")
    }

    private func delete(_ entry: HistoryEntry) {
        pendingDelete = nil
        guard let workout = finished.first(where: { $0.id == entry.id }) else { return }
        context.delete(workout)
        do {
            try context.save()
            entries.removeAll { $0.id == entry.id }
        } catch {
            context.rollback()
            deleteFailed = true
        }
    }

    // MARK: Destination

    @ViewBuilder
    private func destination(_ route: HistoryRoute) -> some View {
        switch route {
        case .workout(let id):
            // Placeholder until the real detail (5.5).
            placeholder(id: id, description: "Workout details are coming soon.")
                .navigationTransition(.zoom(sourceID: id, in: zoom))
        case .editWorkout(let id):
            placeholder(id: id, description: "Editing is coming soon.")
        }
    }

    @ViewBuilder
    private func placeholder(id: UUID, description: String) -> some View {
        if let workout = finished.first(where: { $0.id == id }) {
            ContentUnavailableView(
                workout.name,
                systemImage: "figure.strengthtraining.traditional",
                description: Text(description)
            )
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("history.detail")
        } else {
            ContentUnavailableView(
                "Workout Not Found",
                systemImage: "questionmark.folder",
                description: Text("That workout does not exist.")
            )
            .accessibilityIdentifier("history.detail.missing")
        }
    }
}

/// One History row: name, date, then duration, volume and the PR count with a trophy.
private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.name)
                .font(.headline)
            Text(HistoryList.dateText(entry.startedAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(
                "\(HistoryList.durationText(seconds: entry.durationSeconds)) · \(HistoryList.volumeText(entry.volume, unit: entry.unit))"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if entry.prCount > 0 {
                Label(HistoryList.prText(count: entry.prCount), systemImage: "trophy.fill")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Changes when a finished workout is added, removed or edited, or a setting that changes the numbers does, so the
/// rows are recomputed then and not per render.
private struct Inputs: Hashable {
    let ids: [UUID]
    let newestEdit: Date?
    let unit: String
    let formula: String

    init(_ workouts: [Workout], unit: String, formula: String) {
        ids = workouts.map(\.id)
        newestEdit = workouts.map(\.updatedAt).max()
        self.unit = unit
        self.formula = formula
    }
}

#if DEBUG
    /// Hosts `HistoryView` with its own path for the gallery and the previews.
    struct HistoryDemo: View {
        @State private var path: [HistoryRoute] = []

        var body: some View {
            HistoryView(path: $path)
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
