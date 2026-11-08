//
//  ExerciseDetailView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The exercise detail (task 4.2): a media header, the full wrapping name, and a segmented control over About,
/// History, Charts and Records (4.3). `embedded` drops the navigation chrome (title, Edit) and the
/// edge-to-edge hero (a rounded media card instead), for the logging pane. Edit exists for custom exercises only.
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
    @Environment(SaveErrors.self) private var saveErrors: SaveErrors?
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var customs: [Exercise]
    /// The newest edit among finished workouts: with the store generation it keys the load without reading any rows. The
    /// rows themselves are read on a `WorkoutStatsReader`, never on the main thread.
    @Query(Workout.newestFinishedEdit) private var newest: [Workout]
    @State private var segment: Segment
    @State private var detail = ExerciseDetailData.empty
    /// False until the first load lands: History, Charts and Records show a redacted placeholder rather than their empty
    /// states, which would claim there is no data while it is still being read.
    @State private var detailLoaded = false
    /// True when the first read failed (nothing loaded yet): the data segments offer Retry instead of an empty state.
    @State private var loadFailed = false
    /// Bumped by Retry; part of the load task's id, so it re-runs the read.
    @State private var retries = 0
    /// Bumped at the start of every load; a result applies only while its serial is still the latest. This replaces a
    /// `Task.isCancelled` check: a stray cancellation (iOS fires onDisappear right after a re-push's onAppear) must not
    /// drop the data, while a superseded fingerprint's late result still must.
    @State private var loadSerial = 0
    @State private var isEditing = false
    @State private var removals = 0
    /// The detail column's size, measured outside the content-fitted pane; the hero cap derives from it.
    @State private var columnSize: CGSize?

    init(exerciseID: UUID, embedded: Bool = false, inSplitColumn: Bool = false, initialSegment: Segment = .about) {
        self.exerciseID = exerciseID
        self.embedded = embedded
        self.inSplitColumn = inSplitColumn
        _segment = State(initialValue: initialSegment)
        _customs = Query(filter: #Predicate<Exercise> { $0.id == exerciseID })
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
                    history: FinishedWorkoutsStamp(
                        newestEdit: newest.first?.updatedAt,
                        generation: generation?.value ?? 0
                    ),
                    unit: unit,
                    formula: options.formula,
                    weightType: info.weightType,
                    retries: retries
                )
            ) {
                loadSerial += 1
                let serial = loadSerial
                await SlowLoads.delay()
                await refreshDetail(weightType: info.weightType, serial: serial)
            }
            .accessibilityIdentifier("screen.exerciseDetail")
    }

    /// Folds this exercise's history on a `WorkoutStatsReader` (its own context, off the main thread) and publishes the
    /// sessions, records and history here. What is shown stays until the new values arrive, so a refresh never blanks it.
    /// A result is dropped only when a newer load (`serial`) has started, never because this task was cancelled.
    private func refreshDetail(weightType: WeightType, serial: Int) async {
        // The reader's context reads the store: flush edits the main context has not saved yet.
        context.saveIfChanged(reportingTo: saveErrors)
        do {
            let loaded = try await WorkoutStatsReader.loadExerciseDetail(
                in: context.container,
                exerciseID: exerciseID,
                weightType: weightType,
                options: options
            )
            guard serial == loadSerial else { return }
            detail = loaded
            detailLoaded = true
            loadFailed = false
        } catch {
            // Keep what is already on screen; with nothing loaded yet, say so and offer Retry instead of empty states.
            if !detailLoaded, serial == loadSerial { loadFailed = true }
        }
    }

    /// The embedded pane (already one side of the logging screen's arrangement) and the compact pushed detail are one
    /// scrolling column. The pushed detail at regular width is an `ArrangementView` (one view tree in every pose, so folding
    /// never rebuilds the segment content): the hero, name and segmented control are the primary and the
    /// selected segment's content is the secondary, so book pose puts them either side of the fold (hero left, content
    /// right) and the system split stacks them on the laptop pose (hero above, content below, nothing in the fold band).
    /// Wide, with no fold, it is the same split: side by side when the area is wider than tall, stacked otherwise.
    @ViewBuilder
    private func layout(_ info: ExerciseInfo, library: LibraryExercise?) -> some View {
        content(info, library: library)
            .background {
                Color.clear.onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: {
                    columnSize = $0
                }
            }
            .environment(\.exerciseHeroCapHeight, heroCapHeight)
    }

    /// 35 % of the column's height, and never taller than the 16:9 card the column's width allows (the stacked split's
    /// top pane is the full width, and fits its content using this height as the hero's ideal one).
    private var heroCapHeight: CGFloat {
        guard let columnSize else { return .infinity }
        // 32: the hero's `.padding(.horizontal)`, 16 pt a side.
        return min(columnSize.height * 0.35, max(columnSize.width - 32, 0) * 9 / 16)
    }

    @ViewBuilder
    private func content(_ info: ExerciseInfo, library: LibraryExercise?) -> some View {
        if embedded {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ExerciseMediaHeader(info: info, library: library)
                    summary(info)
                    sections(info, library: library)
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
                        }
                    }
                    .padding(.bottom, 24)
                }
                .stackedPrimaryFitsContent(isSplit: splits)
            } secondary: {
                if splits {
                    ScrollView {
                        sections(info, library: library)
                            .padding(.top)
                            .padding(.bottom, 24)
                    }
                }
            }
            .arrangementViewStyle(.split.axes(splits ? Axis.Set([.horizontal, .vertical]) : Axis.Set()))
        }
    }

    /// Name, tags and the segmented control: everything above the selected segment's content.
    private func summary(_ info: ExerciseInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(info)
            Picker("Section", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Section")
            .accessibilityIdentifier("exerciseDetail.segment")
        }
        .padding(.horizontal)
    }

    /// The selected segment's content, inset by the screen margin. Charts insets itself: its metric chips scroll to the edge.
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
            .padding(.horizontal)
        case .history where loadFailed, .charts where loadFailed, .records where loadFailed:
            loadFailedView
        case .history where !detailLoaded, .charts where !detailLoaded, .records where !detailLoaded:
            ExerciseDetailLoadingPlaceholder()
                .padding(.horizontal)
        case .history:
            ExerciseHistoryView(sessions: detail.history, embedded: embedded)
                .padding(.horizontal)
        case .charts:
            ExerciseChartsView(sessions: detail.sessions, weightType: info.weightType, options: options)
        case .records:
            ExerciseRecordsView(records: detail.records, weightType: info.weightType, unit: unit, embedded: embedded)
                .padding(.horizontal)
        }
    }

    private var loadFailedView: some View {
        ContentUnavailableView {
            Label("Could Not Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text("This exercise's history could not be read.")
        } actions: {
            Button("Retry") {
                loadFailed = false
                retries += 1
            }
            .accessibilityIdentifier("exerciseDetail.retry")
        }
        .accessibilityIdentifier("exerciseDetail.loadFailed")
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

/// Changes when a finished workout is added, removed or edited, or the display unit, the formula or the exercise's weight
/// type (a custom exercise's edit) changes. Built from the newest `updatedAt` and the `StoreGeneration`, so no row is read
/// per body evaluation; every editor stamps `updatedAt` and the bulk writes (import, delete) bump the generation.
private struct Fingerprint: Hashable {
    let history: FinishedWorkoutsStamp
    let unit: WeightUnit
    let formula: E1RMFormula
    let weightType: WeightType
    let retries: Int
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

/// What History, Charts and Records show while their first load is in flight: two session-shaped cards of redacted
/// placeholder rows, so the segment keeps its footprint and nothing claims "no history" before the data has arrived.
private struct ExerciseDetailLoadingPlaceholder: View {
    @ScaledMetric(relativeTo: .body) private var labelWidth = Metrics.setLabelWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<2, id: \.self) { _ in card }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading exercise history")
        .accessibilityIdentifier("exerciseDetail.loading")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Workout name").font(.headline)
                Text("Mon, Jan 1, 2026").font(.footnote)
            }
            .padding(.vertical, 10)
            ForEach(1...3, id: \.self) { number in
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(number)").font(.subheadline.weight(.semibold)).frame(width: labelWidth, alignment: .leading)
                    Text("100 kg × 10").font(.body)
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 8)
            }
        }
        .detailCardStyle()
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
