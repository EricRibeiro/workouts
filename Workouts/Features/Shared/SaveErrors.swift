//
//  SaveErrors.swift
//  Workouts
//

import Observation
import SwiftData
import SwiftUI
import WorkoutsKit

/// Where a failed save is reported (DECISIONS "Errors": a failed `ModelContext.save()` is an alert with the message; the
/// draft is never discarded). One instance lives in the environment; ``View/saveErrorAlert(isEnabled:)`` shows it.
@Observable
final class SaveErrors {
    /// The alert's message while one is showing; `nil` otherwise. A later failure replaces an unacknowledged one.
    var message: String?

    /// How many full-screen editor covers are up. Each hosts its own alert (a presenter under a cover cannot show one), so
    /// the root's stands down while any is.
    var editorCovers = 0

    /// Re-runs the save that failed; `nil` when the reporter has nothing to re-run, and the alert then offers only OK.
    private(set) var retry: (() -> Void)?

    func report(_ error: Error, retry: (() -> Void)? = nil) {
        message = "Could not save: \(error.localizedDescription)."
        self.retry = retry
    }

    /// Clears the alert, optionally running the retry it offered.
    func acknowledge(retrying: Bool = false) {
        let action = retry
        message = nil
        retry = nil
        if retrying { action?() }
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
            errors?.report(error) { [weak errors, weak self] in self?.saveIfChanged(reportingTo: errors) }
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
                    set: { if !$0 { errors?.acknowledge() } }
                )
            ) {
                if errors?.retry != nil {
                    Button("Retry") { errors?.acknowledge(retrying: true) }
                        .accessibilityIdentifier("saveError.retry")
                    Button("Cancel", role: .cancel) {}
                        .accessibilityIdentifier("saveError.cancel")
                } else {
                    Button("OK", role: .cancel) {}
                        .accessibilityIdentifier("saveError.ok")
                }
            } message: {
                Text(errors?.message ?? "")
            }
    }
}

private struct EditorCoverHost: ViewModifier {
    @Environment(SaveErrors.self) private var errors: SaveErrors?
    @Environment(AppNavigation.self) private var navigation: AppNavigation?

    func body(content: Content) -> some View {
        content
            .saveErrorAlert()
            .onAppear {
                errors?.editorCovers += 1
                navigation?.setEditorCoverOnScreen(true)
            }
            .onDisappear {
                errors?.editorCovers = max(0, (errors?.editorCovers ?? 1) - 1)
                navigation?.setEditorCoverOnScreen(false)
            }
    }
}

extension View {
    /// The root of an editor's full-screen cover: hosts the cover's own save-error alert and makes the root's stand down.
    func editorCoverHost() -> some View {
        modifier(EditorCoverHost())
    }

    /// Shows the environment's ``SaveErrors`` message in one alert with OK. Apply it at the root of every presentation
    /// that can report (the root view and the logging cover, which is a full-screen cover of its own). `isEnabled: false`
    /// lets a host stand down while a cover above it shows the alert instead.
    func saveErrorAlert(isEnabled: Bool = true) -> some View {
        modifier(SaveErrorAlert(isEnabled: isEnabled))
    }
}
