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
    /// Owns the rest-end notification; the center holds its delegate weakly, so the app keeps it.
    private let restNotifier: RestNotifier
    /// Mirrors the engine into the Live Activity; kept alive with its intent handler for the life of the app.
    private let activityController: LiveActivityController
    private let intentHandler: EngineActivityIntentHandler?

    @MainActor
    init() {
        let notifier = RestNotifier()
        notifier.activate()
        restNotifier = notifier
        let activityController = LiveActivityController()
        self.activityController = activityController
        do {
            let container = try ModelContainer.workouts(cloudKit: false)
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
            containerError = nil
        } catch {
            container = nil
            engine = nil
            intentHandler = nil
            containerError = error.localizedDescription
        }
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
        if let container, let engine {
            RootView()
                .modelContainer(container)
                .environment(engine)
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
        /// first template (if none runs) and a 5-minute rest, so the Live Activity can be shown without any UI.
        @MainActor
        private static func startSampleWorkoutIfRequested(engine: ActiveWorkoutEngine, context: ModelContext) throws {
            guard ProcessInfo.processInfo.arguments.contains("-startSampleWorkout") else { return }
            if try context.fetchCount(FetchDescriptor<Template>()) == 0 {
                try SampleData.seed(into: context, catalog: LibraryCatalog.bundled(in: .main))
            }
            guard engine.workout == nil else { return }
            var descriptor = FetchDescriptor<Template>(sortBy: [SortDescriptor(\.position), SortDescriptor(\.name)])
            descriptor.fetchLimit = 1
            guard let template = try context.fetch(descriptor).first else { return }
            try engine.start(from: template)
            try engine.startRest(seconds: 300)
        }
    #endif
}
