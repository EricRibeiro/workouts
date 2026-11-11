//
//  PreviewGallery.swift
//  Workouts
//

#if DEBUG
    import SwiftData
    import SwiftUI
    import WorkoutsKit

    /// A named screen the gallery can host. The raw value is the name passed as `-preview <Name>`.
    enum GalleryEntry: String, CaseIterable, Identifiable {
        case gallery = "Gallery"
        case root = "Root"
        case history = "History"
        case workout = "Workout"
        case exercises = "Exercises"
        case settings = "Settings"
        case activeWorkoutCover = "ActiveWorkoutCover"
        case calendar = "Calendar"
        case swatches = "Swatches"
        case exercisePicker = "ExercisePicker"
        case setRow = "SetRow"
        case exercisePickerMulti = "ExercisePickerMulti"
        case setTable = "SetTable"
        case finishSummary = "FinishSummary"
        case exerciseDetail = "ExerciseDetail"
        case workoutDetail = "WorkoutDetail"
        case workoutDetailHealth = "WorkoutDetailHealth"
        case pastEditor = "PastEditor"
        case customExerciseForm = "CustomExerciseForm"
        case customExerciseFormEdit = "CustomExerciseFormEdit"
        case templatePreview = "TemplatePreview"
        case templateEditor = "TemplateEditor"
        case exercisePane = "ExercisePane"
        case exerciseInfoSheet = "ExerciseInfoSheet"
        case heartRateChart = "HeartRateChart"
        case foldPages = "FoldPages"

        var id: String { rawValue }

        /// Every entry except the index itself.
        static var browsable: [GalleryEntry] { allCases.filter { $0 != .gallery } }

        @ViewBuilder
        var view: some View {
            switch self {
            case .gallery: GalleryIndex()
            case .root: RootView()
            case .history: HistoryDemo()
            case .workout: WorkoutView()
            case .exercises: ExercisesView()
            case .settings: SheetHost { SettingsView() }
            case .activeWorkoutCover: ActiveWorkoutCoverDemo()
            case .calendar: SheetHost { CalendarDemo() }
            case .swatches: SwatchesView()
            case .exercisePicker: SheetHost { ExercisePickerView(title: "Add Exercise") { _ in } }
            case .setRow: SetRowDemo()
            case .setTable: SetTableDemo()
            case .finishSummary:
                // `-staticCelebration` draws the Reduce Motion scatter instead of the falling stars, so the
                // accessibility audit measures the same pixels on every run.
                SheetHost {
                    FinishSummaryView(summary: .sample)
                        .environment(
                            \.staticCelebration,
                            ProcessInfo.processInfo.arguments.contains("-staticCelebration")
                        )
                }
            case .exerciseDetail: ExerciseDetailDemo()
            case .workoutDetail: WorkoutDetailDemo()
            case .workoutDetailHealth: WorkoutDetailDemo(withHealth: true)
            case .pastEditor: PastEditorDemo()
            case .customExerciseForm: SheetHost { CustomExerciseFormView(prefill: "Zz Sled Drag") }
            case .customExerciseFormEdit: CustomExerciseFormEditDemo()
            case .templatePreview: TemplatePreviewDemo()
            case .templateEditor: TemplateEditorDemo()
            case .exercisePane: ExercisePaneDemo()
            case .exerciseInfoSheet: ExerciseInfoSheetDemo()
            case .heartRateChart: HeartRateChartDemo()
            case .foldPages: FoldPagesDemo()
            case .exercisePickerMulti:
                ExercisePickerView(title: "Add Exercises", mode: .multiple(add: { _ in }, superset: { _ in }))
            }
        }
    }

    /// Debug root chosen by the launch argument `-preview <Name>`: hosts the same views as the `#Preview`s on the
    /// sample container (built once). Register every new screen as a `GalleryEntry` in the same change.
    enum PreviewGallery {
        /// The name following `-preview` in the launch arguments, if any.
        static func requestedName(in arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
            guard let index = arguments.firstIndex(of: "-preview"), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        /// The one sample environment every entry shares.
        private static let environment = Result { try SampleEnvironment() }

        @ViewBuilder
        static func host(_ name: String) -> some View {
            switch environment {
            case .failure(let error):
                ContentUnavailableView(
                    "Could not build the sample container",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            case .success(let environment):
                if let entry = GalleryEntry(rawValue: name) {
                    entry.view.sampleEnvironment(environment)
                        // A 1 pt invisible marker, so `./dev tree` can wait for the requested screen to be up instead of
                        // dumping whatever is on screen first. An overlay, not an identifier on the content, which would
                        // leak onto descendants without one.
                        .overlay(alignment: .topLeading) {
                            Color.clear
                                .frame(width: 1, height: 1)
                                .allowsHitTesting(false)
                                .accessibilityElement()
                                .accessibilityIdentifier("gallery.host.\(entry.rawValue)")
                        }
                } else {
                    ContentUnavailableView(
                        "Unknown preview \"\(name)\"",
                        systemImage: "questionmark.square.dashed",
                        description: Text(
                            "Valid names: " + GalleryEntry.allCases.map(\.rawValue).joined(separator: ", ")
                        )
                    )
                    .accessibilityIdentifier("gallery.unknown")
                }
            }
        }
    }

    /// The sample model container plus the exercise store built over it: what the `#Preview`s, the gallery and the
    /// snapshot tests inject. `now` fixes the sample workouts' dates; the gallery passes the real clock, the snapshot
    /// tests a fixed instant so the pixels never depend on the day they run.
    struct SampleEnvironment {
        let container: ModelContainer
        let store: ExerciseStore

        init(now: Date = .now) throws {
            let catalog = try LibraryCatalog.bundled(in: .main)
            let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
            try SampleData.seed(into: container.mainContext, catalog: catalog, now: now)
            self.container = container
            store = ExerciseStore(
                catalog: catalog,
                custom: try container.mainContext.fetch(FetchDescriptor<Exercise>())
            )
        }
    }

    extension View {
        /// Hosts the view on the sample container and exercise store.
        func sampleEnvironment(_ environment: SampleEnvironment) -> some View {
            modelContainer(environment.container).environment(environment.store)
        }
    }

    /// Presents `content` as a sheet over an empty screen, the way the app does (a centred card on the regular-width Duo
    /// via `presentationPlacement(.center)`, default detents: none of these five call sites set any), so the gallery's
    /// open and book-pose captures prove the real presentation. Presented at launch; DEBUG only.
    struct SheetHost<Content: View>: View {
        @ViewBuilder let content: () -> Content
        @State private var isPresented = false

        var body: some View {
            Color.clear
                .sheet(isPresented: $isPresented) {
                    content().presentationPlacement(.center)
                }
                .task { isPresented = true }
        }
    }

    /// The exercise info sheet over an empty screen, presented at launch (`-preview ExerciseInfoSheet`).
    struct ExerciseInfoSheetDemo: View {
        @Environment(ExerciseStore.self) private var store
        @State private var exerciseID: UUID?

        var body: some View {
            Color.clear
                .exerciseInfoSheet(exerciseID: $exerciseID)
                .task {
                    // `-infoSheetExercise custom` shows the sample custom exercise (its sheet has an Edit bar).
                    let arguments = ProcessInfo.processInfo.arguments
                    let custom =
                        arguments.firstIndex(of: "-infoSheetExercise").map {
                            arguments.indices.contains($0 + 1) && arguments[$0 + 1] == "custom"
                        } ?? false
                    let name = custom ? SampleData.customExerciseName : "Barbell Bench Press"
                    exerciseID = store.all().first(where: { $0.name == name })?.id
                }
        }
    }

    /// The gallery entry `ActiveWorkoutCover`: the cover over an engine that has started the sample workout (the first
    /// sample template, as `-startSampleWorkout` does for the app), so the logging screen is what gets shown. Without a
    /// running workout the cover only draws its empty state.
    struct ActiveWorkoutCoverDemo: View {
        @Environment(\.modelContext) private var context
        @Environment(ExerciseStore.self) private var store
        @State private var engine: ActiveWorkoutEngine?
        @State private var settings = SettingsStore()
        @State private var failure: String?

        var body: some View {
            Group {
                if let engine {
                    ActiveWorkoutCover(minimise: {}, onFinished: { _ in }, onDiscarded: {})
                        .environment(engine)
                        .environment(settings)
                } else if let failure {
                    ContentUnavailableView(
                        "Could not start the workout",
                        systemImage: "exclamationmark.triangle",
                        description: Text(failure)
                    )
                } else {
                    ProgressView()
                }
            }
            .task { start() }
        }

        private func start() {
            guard engine == nil else { return }
            do {
                let engine = try ActiveWorkoutEngine(
                    context: context,
                    store: store,
                    settings: settings,
                    timedByDefault: { [store] in store.exercise(id: $0)?.isTimed ?? false }
                )
                if engine.workout == nil {
                    var descriptor = FetchDescriptor<Template>(
                        sortBy: [SortDescriptor(\.position), SortDescriptor(\.name)]
                    )
                    descriptor.fetchLimit = 1
                    if let template = try context.fetch(descriptor).first {
                        try engine.start(from: template)
                    } else {
                        try engine.startEmpty()
                    }
                }
                // Three sets done so the screenshot shows done, next and pending rows.
                if let first = (engine.workout?.exercises ?? []).min(by: { $0.position < $1.position }) {
                    for set in (first.sets ?? []).sorted(by: { $0.position < $1.position }).prefix(3) {
                        try? engine.check(set)
                    }
                }
                self.engine = engine
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    /// Browsable list of every gallery entry (`-preview Gallery`).
    struct GalleryIndex: View {
        var body: some View {
            NavigationStack {
                List(GalleryEntry.browsable) { entry in
                    NavigationLink(entry.rawValue) {
                        entry.view
                    }
                    .accessibilityIdentifier("gallery.\(entry.rawValue)")
                }
                .navigationTitle("Gallery")
            }
            .accessibilityIdentifier("screen.gallery")
        }
    }

    #Preview {
        PreviewGallery.host("Gallery")
    }
#endif
