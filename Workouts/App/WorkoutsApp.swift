//
//  WorkoutsApp.swift
//  Workouts
//
//  Created by Eric Ribeiro on 2026-11-03.
//

import SwiftData
import SwiftUI
import WorkoutsKit

@main
struct WorkoutsApp: App {
    /// Local-only until signing and the iCloud entitlement exist (simulator only for now); then `cloudKit: true`.
    private let container: ModelContainer?
    private let containerError: String?
    /// The one engine for the in-progress workout; resumes a running workout from the store at launch.
    private let engine: ActiveWorkoutEngine?
    /// The library plus custom exercises, shared by the engine and the pickers.
    private let store: ExerciseStore?
    /// Owns the rest-end notification; the center holds its delegate weakly, so the app keeps it.
    private let restNotifier: RestNotifier
    /// Mirrors the engine into the Live Activity; kept alive with its intent handler for the life of the app.
    private let activityController: LiveActivityController
    private let intentHandler: EngineActivityIntentHandler?

    @MainActor
    init() {
        #if DEBUG
            // UI tests start from default settings too (the store is in-memory, see makeContainer): earlier runs' taps
            // otherwise persist in UserDefaults. Launch arguments still override through the argument domain.
            if ProcessInfo.processInfo.arguments.contains("-uiTesting"), let domain = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: domain)
            }
        #endif
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
            let engine = try ActiveWorkoutEngine(context: context, store: store, settings: SettingsStore())
            #if DEBUG
                try Self.startSampleWorkoutIfRequested(engine: engine, context: context)
            #endif
            notifier.observe(engine)
            activityController.observe(engine)
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
            #if DEBUG
                // `-preview <Name>` shows a PreviewGallery entry instead of the app (see Debug/PreviewGallery.swift).
                if let name = PreviewGallery.requestedName() {
                    PreviewGallery.host(name)
                } else {
                    appRoot
                }
            #else
                appRoot
            #endif
        }
    }

    @ViewBuilder
    private var appRoot: some View {
        if let container, let engine, let store {
            RootView()
                .modelContainer(container)
                .environment(engine)
                .environment(store)
        } else {
            ContentUnavailableView(
                "Could not open the database",
                systemImage: "exclamationmark.triangle",
                description: Text(containerError ?? "")
            )
        }
    }

    #if DEBUG
        /// `-startSampleWorkout`: seeds the sample data when the store has no templates, then starts a workout from the
        /// first template (if none runs), then always starts a 5-minute rest, so the Live Activity can be shown without any UI.
        @MainActor
        private static func startSampleWorkoutIfRequested(engine: ActiveWorkoutEngine, context: ModelContext) throws {
            guard ProcessInfo.processInfo.arguments.contains("-startSampleWorkout") else { return }
            if try context.fetchCount(FetchDescriptor<Template>()) == 0 {
                try SampleData.seed(into: context, catalog: LibraryCatalog.bundled(in: .main))
            }
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
