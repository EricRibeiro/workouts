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
        case pastEditor = "PastEditor"
        case customExerciseForm = "CustomExerciseForm"
        case customExerciseFormEdit = "CustomExerciseFormEdit"
        case templatePreview = "TemplatePreview"
        case templateEditor = "TemplateEditor"
        case exercisePane = "ExercisePane"

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
            case .settings: SettingsView()
            case .activeWorkoutCover: ActiveWorkoutCover(minimise: {}, onFinished: { _ in }, onDiscarded: {})
            case .calendar: CalendarDemo()
            case .swatches: SwatchesView()
            case .exercisePicker: ExercisePickerView(title: "Add Exercise") { _ in }
            case .setRow: SetRowDemo()
            case .setTable: SetTableDemo()
            case .finishSummary: FinishSummaryView(summary: .sample)
            case .exerciseDetail: ExerciseDetailDemo()
            case .workoutDetail: WorkoutDetailDemo()
            case .pastEditor: PastEditorDemo()
            case .customExerciseForm: CustomExerciseFormView(prefill: "Zz Sled Drag")
            case .customExerciseFormEdit: CustomExerciseFormEditDemo()
            case .templatePreview: TemplatePreviewDemo()
            case .templateEditor: TemplateEditorDemo()
            case .exercisePane: ExercisePaneDemo()
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
