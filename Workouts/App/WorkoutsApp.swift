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

    @MainActor
    init() {
        let notifier = RestNotifier()
        notifier.activate()
        restNotifier = notifier
        do {
            let container = try ModelContainer.workouts(cloudKit: false)
            let context = container.mainContext
            let store = ExerciseStore(
                catalog: try LibraryCatalog.bundled(in: .main),
                custom: try context.fetch(FetchDescriptor<Exercise>())
            )
            let engine = try ActiveWorkoutEngine(context: context, store: store, settings: SettingsStore())
            notifier.observe(engine)
            self.container = container
            self.engine = engine
            containerError = nil
        } catch {
            container = nil
            engine = nil
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
}
