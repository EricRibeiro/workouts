//
//  ExerciseDetailView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The exercise detail (task 4.2): a media header, the full wrapping name, and a segmented control over About,
/// History, Charts and Records (4.3). `embedded` drops the navigation chrome (title, Edit) and the
/// edge-to-edge hero (a rounded media card instead), for the logging pane; the sticky note is editable in both. Edit exists for custom exercises only.
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
    /// The detail column of a split view (the Exercises tab) is already one side of the fold and too narrow to split again.
    var inSplitColumn = false

    @Environment(ExerciseStore.self) private var store
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @Environment(StoreGeneration.self) private var generation: StoreGeneration?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var customs: [Exercise]
    /// Only this exercise's rows in finished workouts (their sets and workouts prefetched), not every workout.
    @Query private var rows: [WorkoutExercise]
    @State private var segment: Segment
    @State private var records: [ExerciseRecord] = []
    @State private var sessions: [Session] = []
    @State private var history: [ExerciseHistorySession] = []
    @State private var isEditing = false
    @State private var removals = 0

    init(exerciseID: UUID, embedded: Bool = false, inSplitColumn: Bool = false, initialSegment: Segment = .about) {
        self.exerciseID = exerciseID
        self.embedded = embedded
        self.inSplitColumn = inSplitColumn
        _segment = State(initialValue: initialSegment)
        _customs = Query(filter: #Predicate<Exercise> { $0.id == exerciseID })
        _rows = Query(ExerciseBestSets.rowsDescriptor(exerciseID: exerciseID))
    }

    var body: some View {
        Group {
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
        // On the Group, which outlives both the edit sheet and a deleted exercise's content (the branch flips).
        .sensoryFeedback(.warning, trigger: removals)
    }

    private var unit: WeightUnit { (settings ?? SettingsStore()).defaultUnit }
    private var options: RecordsOptions {
        RecordsOptions(formula: (settings ?? SettingsStore()).e1rmFormula, displayUnit: unit)
    }

    private func content(_ info: ExerciseInfo) -> some View {
        let library = info.isCustom ? nil : store.catalog.exercise(id: info.id)
        return layout(info, library: library)
            .modifier(DetailChrome(showsEdit: info.isCustom && !embedded, embedded: embedded) { isEditing = true })
            .sheet(isPresented: $isEditing) {
                CustomExerciseFormView(editing: exerciseID, onRemoved: { removals += 1 })
                    .presentationPlacement(.center)
            }
            .task(
                id: Fingerprint(
                    rows,
                    generation: generation?.value ?? 0,
                    unit: unit,
                    formula: options.formula,
                    weightType: info.weightType
                )
            ) {
                await SlowLoads.delay()
                let found = ExerciseBestSets.sessions(forRows: rows, weightType: info.weightType)
                sessions = found
                records = WorkoutsKit.records(found, weightType: info.weightType, options: options)
                history = ExerciseHistory.sessions(
                    found,
                    names: ExerciseBestSets.workoutNames(of: rows),
                    weightType: info.weightType,
                    options: options
                )
            }
            .accessibilityIdentifier("screen.exerciseDetail")
    }

    /// The embedded pane (already one side of the logging screen's arrangement) and the compact pushed detail are one
    /// scrolling column. The pushed detail at regular width is an `ArrangementView` (one view tree in every pose, so folding
    /// never rebuilds the segment content): the hero, name, sticky note and segmented control are the primary and the
    /// selected segment's content is the secondary, so book pose puts them either side of the fold (hero left, content
    /// right) and the system split stacks them on the laptop pose (hero above, content below, nothing in the fold band).
    /// Wide, with no fold, it is the same split: side by side when the area is wider than tall, stacked otherwise.
    @ViewBuilder
    private func layout(_ info: ExerciseInfo, library: LibraryExercise?) -> some View {
        if embedded {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ExerciseMediaHeader(info: info, library: library)
                    summary(info)
                    sections(info, library: library)
                        .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
        } else {
            let splits = horizontalSizeClass == .regular && !inSplitColumn
            ArrangementView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ExerciseMediaHeader(info: info, library: library)
                        summary(info)
                        if !splits {
                            sections(info, library: library)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .stackedPrimaryFitsContent(isSplit: splits)
            } secondary: {
                if splits {
                    ScrollView {
                        sections(info, library: library)
                            .padding([.horizontal, .top])
                            .padding(.bottom, 24)
                    }
                }
            }
            .arrangementViewStyle(.split.axes(splits ? Axis.Set([.horizontal, .vertical]) : Axis.Set()))
        }
    }

    /// Name, tags, sticky note and the segmented control: everything above the selected segment's content.
    private func summary(_ info: ExerciseInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(info)
            StickyNoteView(exerciseID: info.id)
            Picker("Section", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Section")
            .accessibilityIdentifier("exerciseDetail.segment")
        }
        .padding(.horizontal)
    }

    /// The selected segment's content.
    @ViewBuilder
    private func sections(_ info: ExerciseInfo, library: LibraryExercise?) -> some View {
        switch segment {
        case .about:
            ExerciseAboutSection(
                info: info,
                library: library,
                labels: store.catalog.labels,
                customInstructions: customs.first?.instructions ?? []
            )
        case .history:
            ExerciseHistoryView(sessions: history, embedded: embedded)
        case .charts:
            ExerciseChartsView(sessions: sessions, weightType: info.weightType, options: options)
        case .records:
            ExerciseRecordsView(records: records, weightType: info.weightType, unit: unit, embedded: embedded)
        }
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

/// The pushed detail's navigation chrome: an empty inline title and, for custom exercises, Edit. The embedded pane has
/// none, so it never touches its host's title or toolbar.
private struct DetailChrome: ViewModifier {
    let showsEdit: Bool
    let embedded: Bool
    let edit: () -> Void

    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if showsEdit {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Edit", systemImage: "pencil", action: edit)
                                .accessibilityLabel("Edit")
                                .accessibilityIdentifier("exerciseDetail.edit")
                        }
                    }
                }
        }
    }
}

/// Changes when a finished workout with this exercise is added, removed or edited, or the display unit, the formula or
/// the exercise's weight type (a custom exercise's edit) changes.
private struct Fingerprint: Hashable {
    let count: Int
    let newestEdit: Date?
    /// `StoreGeneration`: an import can update an older workout without moving the count or the newest stamp.
    let generation: Int
    let unit: WeightUnit
    let formula: E1RMFormula
    let weightType: WeightType

    init(_ rows: [WorkoutExercise], generation: Int, unit: WeightUnit, formula: E1RMFormula, weightType: WeightType) {
        count = rows.count
        self.generation = generation
        // A row's own stamp, or its workout's (a rename or a date change stamps only the workout).
        newestEdit = rows.flatMap { [$0.updatedAt, $0.workout?.updatedAt] }.compactMap { $0 }.max()
        self.unit = unit
        self.formula = formula
        self.weightType = weightType
    }
}

/// In the stacked split (open, taller than wide) the primary pane takes the height of its content, so the secondary
/// follows directly under the segmented control instead of after a half-height pane with a gap at its bottom. Side by
/// side (open wide, book pose) the primary keeps the full height. The arrangement publishes its axis to the primary's
/// subtree, so this reads it there.
private struct StackedPrimaryFitsContent: ViewModifier {
    let isSplit: Bool
    @Environment(\.splitArrangementAxis) private var axis

    func body(content: Content) -> some View {
        content.splitArrangementFixedLayoutSize(horizontal: false, vertical: isSplit && axis == .vertical)
    }
}

extension View {
    fileprivate func stackedPrimaryFitsContent(isSplit: Bool) -> some View {
        modifier(StackedPrimaryFitsContent(isSplit: isSplit))
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

        @State private var path: [UUID] = []

        var body: some View {
            // Pushed onto an empty root, as the Exercises tab does. A root detail has no back button or toolbar item,
            // and a navigation bar with no items gets no strip on the closed Duo, so the system clock would vanish.
            NavigationStack(path: $path) {
                Color.clear
                    .navigationDestination(for: UUID.self) { id in
                        ExerciseDetailView(exerciseID: id, initialSegment: initialSegment)
                    }
            }
            .task {
                if let id = store.all().first(where: { $0.name == "Barbell Bench Press" })?.id, path.isEmpty {
                    path = [id]
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
