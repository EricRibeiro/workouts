//
//  SaveErrors.swift
//  Workouts
//

import Observation
import SwiftData
import SwiftUI

/// Where a failed save is reported (DECISIONS "Errors": a failed `ModelContext.save()` is an alert with the message; the
/// draft is never discarded). One instance lives in the environment; ``View/saveErrorAlert(isEnabled:)`` shows it.
@Observable
final class SaveErrors {
    /// The alert's message while one is showing; `nil` otherwise. A later failure replaces an unacknowledged one.
    var message: String?

    func report(_ error: Error) {
        message = "Could not save: \(error.localizedDescription)."
    }
}

extension ModelContext {
    /// Saves pending edits, reporting a failure to `errors`. Used before a `WorkoutStatsReader` load: the reader's own
    /// context reads the store, so unsaved main-context edits must be flushed first.
    func saveIfChanged(reportingTo errors: SaveErrors?) {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            errors?.report(error)
        }
    }
}

private struct SaveErrorAlert: ViewModifier {
    let isEnabled: Bool
    @Environment(SaveErrors.self) private var errors: SaveErrors?

    func body(content: Content) -> some View {
        content
            .alert(
                "Could Not Save",
                isPresented: Binding(
                    get: { isEnabled && errors?.message != nil },
                    set: { if !$0 { errors?.message = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
                    .accessibilityIdentifier("saveError.ok")
            } message: {
                Text(errors?.message ?? "")
            }
    }
}

extension View {
    /// Shows the environment's ``SaveErrors`` message in one alert with OK. Apply it at the root of every presentation
    /// that can report (the root view and the logging cover, which is a full-screen cover of its own). `isEnabled: false`
    /// lets a host stand down while a cover above it shows the alert instead.
    func saveErrorAlert(isEnabled: Bool = true) -> some View {
        modifier(SaveErrorAlert(isEnabled: isEnabled))
    }
}
