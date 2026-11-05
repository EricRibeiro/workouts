//
//  WorkoutsApp.swift
//  Workouts
//
//  Created by Eric Ribeiro on 2026-11-03.
//

import ActivityKit
import SwiftData
import SwiftUI
import WorkoutsKit

@main
struct WorkoutsApp: App {
    /// Local-only: the iCloud entitlement exists (7.1) but SwiftData sync stays off until PLAN 8.1 (JC54).
    private let container: ModelContainer?
    private let containerError: String?
    /// The one engine for the in-progress workout; resumes a running workout from the store at launch.
    private let engine: ActiveWorkoutEngine?
    /// The one settings store: the engine reads it, and every view reads or edits it through the environment.
    private let settings: SettingsStore
    /// The library plus custom exercises, shared by the engine and the pickers.
    private let store: ExerciseStore?
    /// Owns the rest-end notification; the center holds its delegate weakly, so the app keeps it.
    private let restNotifier: RestNotifier
    /// Mirrors the engine into the Live Activity; kept alive with its intent handler for the life of the app.
    private let activityController: LiveActivityController
    /// Where save failures are reported; the root view and the logging cover each host its alert.
    private let saveErrors = SaveErrors()
    /// Bumped by bulk writes that `updatedAt` does not show (an import); the history caches fold it into their keys.
    private let storeGeneration = StoreGeneration()
    /// Looks up the Apple Fitness workout behind each finished workout; its source is chosen once, here at launch.
    private let healthService: HealthEnrichmentService
    private let intentHandler: EngineActivityIntentHandler?

    @MainActor
    init() {
        #if DEBUG
            // UI tests start from default settings too (the store is in-memory, see makeContainer): earlier runs' taps
            // otherwise persist in UserDefaults. Launch arguments still override through the argument domain.
            if ProcessInfo.processInfo.arguments.contains("-uiTesting"), let domain = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: domain)
            }
            // `-seedHealth`: writes a sample Fitness workout into the simulator's Health store (docs/port/healthkit.md).
            HealthSeeder.seedIfRequested()
        #endif
        let settings = SettingsStore()
        self.settings = settings
        healthService = HealthEnrichmentService.atLaunch(settings: settings)
        let notifier = RestNotifier()
        notifier.activate()
        restNotifier = notifier
        let activityController = LiveActivityController()
        self.activityController = activityController
        do {
            let container = try Self.makeContainer()
            let context = container.mainContext
            let store = ExerciseStore(
                catalog: try LibraryCatalog.bundled(in: .main),
                custom: try context.fetch(FetchDescriptor<Exercise>())
            )
            let engine = try ActiveWorkoutEngine(context: context, store: store, settings: settings)
            #if DEBUG
                try Self.startSampleWorkoutIfRequested(engine: engine, context: context)
                try Self.seedOldWorkoutIfRequested(context: context)
            #endif
            notifier.observe(engine)
            if Self.wantsLiveActivity {
                activityController.observe(engine)
            } else {
                Self.endLiveActivities()
            }
            let handler = EngineActivityIntentHandler(engine: engine)
            ActivityIntentRouter.handler = handler
            intentHandler = handler
            self.container = container
            self.engine = engine
            self.store = store
            containerError = nil
        } catch {
            container = nil
            engine = nil
            store = nil
            intentHandler = nil
            containerError = error.localizedDescription
        }
    }

    /// Debug builds use a throwaway in-memory store for UI tests (`-uiTesting`) and the `-preview <Name>` gallery, so a
    /// workout left in progress by an earlier run is never resumed (with its Live Activity and rest notifications).
    /// Release builds always open the persistent store.
    @MainActor
    private static func makeContainer() throws -> ModelContainer {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            let inMemory = arguments.contains("-uiTesting") || PreviewGallery.requestedName() != nil
            return try ModelContainer.workouts(inMemory: inMemory, cloudKit: false)
        #else
            return try ModelContainer.workouts(cloudKit: false)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            // One call at the scene root (app and gallery alike): sheets and full-screen covers inherit it.
            content.preferredColorScheme(settings.appearance.colorScheme)
        }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
            // `-preview <Name>` shows a PreviewGallery entry instead of the app (see Debug/PreviewGallery.swift).
            if let name = PreviewGallery.requestedName() {
                PreviewGallery.host(name)
                    .environment(settings)
                    .environment(healthService)
            } else {
                appRoot
            }
        #else
            appRoot
        #endif
    }

    @ViewBuilder
    private var appRoot: some View {
        if let container, let engine, let store {
            RootView()
                .modelContainer(container)
                .environment(engine)
                .environment(store)
                .environment(settings)
                .environment(saveErrors)
                .environment(storeGeneration)
                .environment(healthService)
        } else {
            ContentUnavailableView(
                "Could not open the database",
                systemImage: "exclamationmark.triangle",
                description: Text(containerError ?? "")
            )
        }
    }

    /// UI tests (`-uiTesting`) run without a Live Activity unless they pass `-liveActivity`: an activity left running when the
    /// next build is installed makes iOS relaunch the widget extension from the deleted bundle, which crashes it
    /// (`WorkoutsLiveActivity` reports under containermanagerd's `Dead/`, 2026-11-03).
    private static var wantsLiveActivity: Bool {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            return !arguments.contains("-uiTesting") || arguments.contains("-liveActivity")
        #else
            return true
        #endif
    }

    /// Ends any activity a previous run left behind.
    private static func endLiveActivities() {
        Task {
            for activity in Activity<WorkoutActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    #if DEBUG
        /// `-seedOldWorkout`: inserts one finished workout "Old Backfill Workout" that ended 30 days ago and was never
        /// checked against Health, so a UI test can prove the Fitness backfill (the routine lookup gives up after 7 days).
        @MainActor
        private static func seedOldWorkoutIfRequested(context: ModelContext) throws {
            guard ProcessInfo.processInfo.arguments.contains("-seedOldWorkout") else { return }
            let start = Date.now.addingTimeInterval(-30 * 86400)
            let workout = Workout(
                name: "Old Backfill Workout",
                startedAt: start,
                finishedAt: start.addingTimeInterval(50 * 60),
                createdAt: start,
                updatedAt: start
            )
            context.insert(workout)
            let row = WorkoutExercise(exerciseName: "Back Squat", position: 0, unit: .kg, updatedAt: start)
            context.insert(row)
            row.workout = workout
            let set = WorkoutSet(
                position: 0,
                weight: 100,
                reps: 5,
                completed: true,
                completedAt: start.addingTimeInterval(600)
            )
            context.insert(set)
            set.workoutExercise = row
            try context.save()
        }

        /// `-seedSampleData`: seeds the sample data when the store has no templates and stops there.
        /// `-sampleWorkouts <n>`: seeds n finished workouts over ~2 years instead of the default 50 (and stops there).
        /// `-startSampleWorkout`: seeds the sample data when the store has no templates, then starts a workout from the
        /// first template (if none runs), then always starts a 5-minute rest, so the Live Activity can be shown without any UI.
        @MainActor
        private static func startSampleWorkoutIfRequested(engine: ActiveWorkoutEngine, context: ModelContext) throws {
            let arguments = ProcessInfo.processInfo.arguments
            let starts = arguments.contains("-startSampleWorkout")
            // `-sampleWorkouts <n>`: seeds n finished workouts spread over ~2 years (performance runs, PLAN 6.4).
            let scaled = arguments.firstIndex(of: "-sampleWorkouts").flatMap { index in
                arguments.indices.contains(index + 1) ? Int(arguments[index + 1]) : nil
            }
            guard starts || scaled != nil || arguments.contains("-seedSampleData") else { return }
            if try context.fetchCount(FetchDescriptor<Template>()) == 0 {
                let catalog = try LibraryCatalog.bundled(in: .main)
                if let scaled {
                    try SampleData.seed(into: context, catalog: catalog, workoutCount: scaled, spanDays: 730)
                } else {
                    try SampleData.seed(into: context, catalog: catalog)
                }
            }
            guard starts else { return }
            if engine.workout == nil {
                var descriptor = FetchDescriptor<Template>(sortBy: [SortDescriptor(\.position), SortDescriptor(\.name)])
                descriptor.fetchLimit = 1
                guard let template = try context.fetch(descriptor).first else { return }
                try engine.start(from: template)
            }
            // `-sampleRestSeconds N` (launch arguments land in UserDefaults) shortens it, e.g. to prove the rest-end
            // notification.
            let seconds = UserDefaults.standard.integer(forKey: "sampleRestSeconds")
            try engine.startRest(seconds: seconds > 0 ? seconds : 300)
        }
    #endif
}
