//
//  ExerciseDetailView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The exercise detail (task 4.2): a media header, the full wrapping name, and a segmented control over About,
/// History, Charts and Records (4.3). `embedded` drops the navigation chrome (title, Edit) and the
/// edge-to-edge hero, for the logging pane. Edit exists for custom exercises only.
struct ExerciseDetailView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case about = "About"
        case history = "History"
        case charts = "Charts"
        case records = "Records"

        var id: String { rawValue }
    }

    let exerciseID: UUID
    var embedded = false

    @Environment(ExerciseStore.self) private var store
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @Query private var customs: [Exercise]
    @Query(filter: #Predicate<Workout> { $0.finishedAt != nil }) private var finished: [Workout]
    @State private var segment: Segment
    @State private var records: [ExerciseRecord] = []
    @State private var sessions: [Session] = []
    @State private var history: [ExerciseHistorySession] = []
    @State private var isEditing = false

    init(exerciseID: UUID, embedded: Bool = false, initialSegment: Segment = .about) {
        self.exerciseID = exerciseID
        self.embedded = embedded
        _segment = State(initialValue: initialSegment)
        _customs = Query(filter: #Predicate<Exercise> { $0.id == exerciseID })
    }

    var body: some View {
        if let info = store.exercise(id: exerciseID) {
            content(info)
        } else {
            ContentUnavailableView(
                "That exercise does not exist.",
                systemImage: "questionmark.folder"
            )
            .accessibilityIdentifier("screen.exerciseDetail")
        }
    }

    private var unit: WeightUnit { (settings ?? SettingsStore()).defaultUnit }
    private var options: RecordsOptions {
        RecordsOptions(formula: (settings ?? SettingsStore()).e1rmFormula, displayUnit: unit)
    }

    private func content(_ info: ExerciseInfo) -> some View {
        let library = info.isCustom ? nil : store.catalog.exercise(id: info.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ExerciseMediaHeader(info: info, library: library, embedded: embedded)
                VStack(alignment: .leading, spacing: 16) {
                    header(info)
                    Picker("Section", selection: $segment) {
                        ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Section")
                    .accessibilityIdentifier("exerciseDetail.segment")
                    switch segment {
                    case .about:
                        ExerciseAboutSection(
                            info: info,
                            library: library,
                            labels: store.catalog.labels,
                            customInstructions: customs.first?.instructions ?? []
                        )
                    case .history:
                        ExerciseHistoryView(sessions: history)
                    case .charts:
                        ExerciseChartsView(sessions: sessions, weightType: info.weightType, options: options)
                    case .records:
                        ExerciseRecordsView(records: records, weightType: info.weightType, unit: unit)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if info.isCustom && !embedded {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                        .accessibilityLabel("Edit")
                        .accessibilityIdentifier("exerciseDetail.edit")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            CustomExerciseFormView(editing: exerciseID)
                .presentationPlacement(.center)
        }
        .task(id: Fingerprint(finished, unit: unit, formula: options.formula)) {
            let found =
                ExerciseBestSets.sessions(from: finished) { id in
                    id == info.id ? info.weightType : nil
                }[info.id] ?? []
            sessions = found
            records = WorkoutsKit.records(found, weightType: info.weightType, options: options)
            let names = Dictionary(finished.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            history = ExerciseHistory.sessions(found, names: names, weightType: info.weightType, options: options)
        }
        .accessibilityIdentifier("screen.exerciseDetail")
    }

    private func header(_ info: ExerciseInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(info.name)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("exerciseDetail.name")
            let tags = ExerciseRow.tagText(for: info)
            if !tags.isEmpty {
                Text(tags)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Changes when a finished workout is added, removed or edited, or the display unit or formula changes.
private struct Fingerprint: Hashable {
    let count: Int
    let newestEdit: Date?
    let unit: WeightUnit
    let formula: E1RMFormula

    init(_ workouts: [Workout], unit: WeightUnit, formula: E1RMFormula) {
        count = workouts.count
        newestEdit = workouts.map(\.updatedAt).max()
        self.unit = unit
        self.formula = formula
    }
}

#if DEBUG
    /// The gallery host: Barbell Bench Press from the sample history, in a stack like the Exercises tab pushes it.
    struct ExerciseDetailDemo: View {
        @Environment(ExerciseStore.self) private var store
        /// `-detailSegment Records` opens the gallery entry on that segment.
        var initialSegment: ExerciseDetailView.Segment {
            let arguments = ProcessInfo.processInfo.arguments
            let index = arguments.firstIndex(of: "-detailSegment")
            let name = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            return name.flatMap(ExerciseDetailView.Segment.init(rawValue:)) ?? .about
        }

        var body: some View {
            NavigationStack {
                if let id = store.all().first(where: { $0.name == "Barbell Bench Press" })?.id {
                    ExerciseDetailView(exerciseID: id, initialSegment: initialSegment)
                } else {
                    ContentUnavailableView("Barbell Bench Press is not in the library", systemImage: "questionmark")
                }
            }
        }
    }

    #Preview("Large") {
        PreviewGallery.host("ExerciseDetail")
            .dynamicTypeSize(.large)
    }

    #Preview("Accessibility 3") {
        PreviewGallery.host("ExerciseDetail")
            .dynamicTypeSize(.accessibility3)
    }
#endif
