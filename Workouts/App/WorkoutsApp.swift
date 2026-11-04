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

    init() {
        do {
            container = try ModelContainer.workouts(cloudKit: false)
            containerError = nil
        } catch {
            container = nil
            containerError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView().modelContainer(container)
            } else {
                ContentUnavailableView(
                    "Could not open the database",
                    systemImage: "exclamationmark.triangle",
                    description: Text(containerError ?? "")
                )
            }
        }
    }
}
