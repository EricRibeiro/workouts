//
//  RestToolbarGroup.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// Skip and +30 s for the running rest, as one toolbar group. The logging screen and the minimised workout's resume control
/// each show it (identifiers `<idPrefix>.skip` and `<idPrefix>.plus30`); the caller decides when a rest is counting down.
struct RestToolbarGroup: ToolbarContent {
    let engine: ActiveWorkoutEngine
    let idPrefix: String
    var errors: SaveErrors?

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Skip", systemImage: "forward.end") { perform { try engine.skipRest() } }
                .accessibilityLabel("Skip rest")
                .accessibilityIdentifier("\(idPrefix).skip")
            Button("+30 s", systemImage: "goforward.30") { perform { try engine.adjustRest(by: 30) } }
                .accessibilityLabel("Add 30 seconds")
                .accessibilityIdentifier("\(idPrefix).plus30")
        }
    }

    /// Runs an engine call and reports a failure through the save-error alert.
    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errors?.report(error)
        }
    }
}
