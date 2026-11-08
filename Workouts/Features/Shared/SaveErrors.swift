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

    /// The presentations (covers, sheets) hosting their own alert, bottom to top. A presenter under another presentation
    /// cannot show one, so the root's stands down while any is up, and only the topmost host (``isTopmost(_:)``) shows it.
    /// Hosts are tracked by id, not by count: a dismissed sheet's `onDisappear` can land after the next cover's `onAppear`.
    private(set) var hosts: [UUID] = []

    var hostDepth: Int { hosts.count }

    func enterHost(_ id: UUID) {
        hosts.removeAll { $0 == id }
        hosts.append(id)
    }

    func leaveHost(_ id: UUID) {
        hosts.removeAll { $0 == id }
    }

    /// Whether `id` is the presentation currently on top, the only one whose alert may be enabled.
    func isTopmost(_ id: UUID) -> Bool {
        hosts.last == id
    }

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

/// Hosts a presentation's own alert, enabled only while it is the topmost host.
private struct SaveErrorHost: ViewModifier {
    @Environment(SaveErrors.self) private var errors: SaveErrors?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .saveErrorAlert(isEnabled: errors?.isTopmost(id) ?? false)
            .onAppear { errors?.enterHost(id) }
            .onDisappear { errors?.leaveHost(id) }
    }
}

private struct EditorCoverHost: ViewModifier {
    @Environment(AppNavigation.self) private var navigation: AppNavigation?

    func body(content: Content) -> some View {
        content
            .saveErrorHost()
            .onAppear { navigation?.setEditorCoverOnScreen(true) }
            .onDisappear { navigation?.setEditorCoverOnScreen(false) }
    }
}

extension View {
    /// The root of a sheet that can report a save failure (the root's alert sits under it and cannot present): hosts the
    /// sheet's own alert and makes the root's stand down while the sheet is up.
    func sheetSaveErrorHost() -> some View {
        saveErrorHost()
    }

    /// The root of the workout cover: hosts its own alert, disabled while a sheet above it hosts one. The root's stands
    /// down through `isWorkoutCoverPresented`.
    func workoutCoverSaveErrorHost() -> some View {
        saveErrorHost()
    }

    fileprivate func saveErrorHost() -> some View {
        modifier(SaveErrorHost())
    }

    /// The root of an editor's full-screen cover: hosts the cover's own save-error alert and makes the root's stand down.
    func editorCoverHost() -> some View {
        modifier(EditorCoverHost())
    }

    /// Shows the environment's ``SaveErrors`` message in one alert with OK. Apply it at the root of every presentation
    /// that can report (the root view; covers and sheets use the host modifiers above). `isEnabled: false`
    /// lets a host stand down while a cover above it shows the alert instead.
    func saveErrorAlert(isEnabled: Bool = true) -> some View {
        modifier(SaveErrorAlert(isEnabled: isEnabled))
    }
}
