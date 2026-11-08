//
//  FinishFlow.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The Finish dialogs of the logging screen (`active-workout.md` section 3, Finish, and section 4, "Finish failed").
///
/// The toolbar's Finish button calls ``begin(engine:onFinished:onDiscarded:)``; ``View/finishFlow(_:)`` presents whichever
/// dialog the engine's summary asks for and runs the chosen action. The workout is only ever discarded by an explicit
/// choice: a failed save leaves it in place.
@Observable
final class FinishFlowState {
    /// The dialog being shown, if any.
    fileprivate var dialog: FinishDialog?
    /// The text of the "Could not save" alert, if it is showing.
    fileprivate(set) var errorMessage: String?
    /// The text of the "Workout Saved" alert, shown when Finish saved the workout but building the summary then failed.
    /// Acknowledging it ends the workout and closes the cover (``acknowledgeSavedWithoutSummary()``).
    fileprivate(set) var savedMessage: String?
    /// Whether the title menu's "Discard workout?" confirmation is showing.
    fileprivate var isDiscardConfirmationShown = false
    /// Counts confirmed destructive choices; drives the `.warning` haptic.
    fileprivate var destructiveCount = 0

    private var engine: ActiveWorkoutEngine?
    private var onFinished: (FinishSummary) -> Void = { _ in }
    private var onDiscarded: () -> Void = {}
    private var onSavedWithoutSummary: (UUID?) -> Void = { _ in }
    /// The id of the workout being finished, read before the save lets go of it: the "saved, no summary" hand-off needs it.
    private var finishingWorkoutID: UUID?
    /// What "Retry" in the error alert repeats.
    private var retry: (() -> Void)?

    /// Tap on Finish: asks the engine which dialog applies and shows it, or finishes at once when every set is checked.
    func begin(
        engine: ActiveWorkoutEngine,
        onFinished: @escaping (FinishSummary) -> Void,
        onDiscarded: @escaping () -> Void,
        onSavedWithoutSummary: ((UUID?) -> Void)? = nil
    ) {
        self.engine = engine
        configure(
            onFinished: onFinished,
            onDiscarded: onDiscarded,
            onSavedWithoutSummary: onSavedWithoutSummary
        )
        do {
            let dialog = try engine.finishDialog()
            if dialog == .none {
                finish(.discard)
            } else {
                self.dialog = dialog
            }
        } catch {
            fail(error) { [weak self] in
                self?.begin(
                    engine: engine,
                    onFinished: onFinished,
                    onDiscarded: onDiscarded,
                    onSavedWithoutSummary: onSavedWithoutSummary
                )
            }
        }
    }

    /// Sets what a finished or ended workout hands on to (also how the tests drive ``run(finish:isWorkoutGone:retry:)``).
    /// `onSavedWithoutSummary` runs when the save went through but the summary could not be built (it defaults to
    /// `onDiscarded`, which only ends the workout).
    func configure(
        onFinished: @escaping (FinishSummary) -> Void,
        onDiscarded: @escaping () -> Void,
        onSavedWithoutSummary: ((UUID?) -> Void)? = nil
    ) {
        self.onFinished = onFinished
        self.onDiscarded = onDiscarded
        self.onSavedWithoutSummary = onSavedWithoutSummary ?? { _ in onDiscarded() }
    }

    /// Title menu, Discard Workout: asks for confirmation; confirming runs the same discard as the Finish dialog.
    func requestDiscard(engine: ActiveWorkoutEngine, onDiscarded: @escaping () -> Void) {
        self.engine = engine
        self.onDiscarded = onDiscarded
        isDiscardConfirmationShown = true
    }

    fileprivate func finish(_ unfinished: UnfinishedSets) {
        guard let engine else { return }
        run(
            finish: { try engine.finish(unfinished: unfinished) },
            isWorkoutGone: { engine.workout == nil },
            retry: { [weak self] in self?.finish(unfinished) },
            workoutID: engine.workout?.id
        )
    }

    /// Runs `finish` and hands its summary to `onFinished`. A throw while the workout is still there is a failed save
    /// (Retry offered). A throw after the engine let go of the workout means the save succeeded and only the summary
    /// failed: Retry would find nothing to finish, so the person is told it is saved and the cover closes to History.
    func run(
        finish: () throws -> FinishSummary,
        isWorkoutGone: () -> Bool,
        retry: @escaping () -> Void,
        workoutID: UUID? = nil
    ) {
        finishingWorkoutID = workoutID
        do {
            onFinished(try finish())
        } catch {
            if isWorkoutGone() {
                savedMessage =
                    "The workout was saved, but its summary could not be built: \(error.localizedDescription). You can find it in History."
            } else {
                fail(error, retry: retry)
            }
        }
    }

    /// OK on the "Workout Saved" alert: the workout is already saved, so hand it on as a finish minus the summary sheet
    /// (Health pickup, the "Update Template?" question) and close the cover.
    func acknowledgeSavedWithoutSummary() {
        savedMessage = nil
        onSavedWithoutSummary(finishingWorkoutID)
        finishingWorkoutID = nil
    }

    fileprivate func discardWorkout() {
        guard let engine else { return }
        do {
            try engine.discard()
            onDiscarded()
        } catch {
            fail(error) { [weak self] in self?.discardWorkout() }
        }
    }

    func retryAfterError() {
        let action = retry
        retry = nil
        action?()
    }

    private func fail(_ error: Error, retry: @escaping () -> Void) {
        self.retry = retry
        errorMessage =
            "Could not save the workout: \(error.localizedDescription). It is still here and nothing is lost."
    }
}

extension View {
    /// Presents the Finish confirmation dialogs driven by `state`. Attach it to the Finish button, so a popover (regular
    /// width) points at it.
    func finishFlow(_ state: FinishFlowState) -> some View {
        modifier(FinishFlow(state: state))
    }

    /// Presents the failure alerts driven by `state`. Attach it to a view that stays mounted through the finish
    /// transition (the cover's stack): the Finish button is gone once the workout is saved.
    func finishFlowAlerts(_ state: FinishFlowState) -> some View {
        modifier(FinishFlowAlerts(state: state))
    }
}

private struct FinishFlow: ViewModifier {
    @Bindable var state: FinishFlowState

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Nothing logged yet",
                isPresented: isShowing { $0 == .nothingLogged },
                titleVisibility: .visible
            ) {
                Button("Discard Workout", role: .destructive) {
                    state.destructiveCount += 1
                    state.discardWorkout()
                }
                .accessibilityIdentifier("finish.discardWorkout")
                Button("Keep Going", role: .cancel) {}
                    .accessibilityIdentifier("finish.keepGoing")
            } message: {
                Text("Check off at least one set to save this workout, or discard it.")
            }
            .confirmationDialog(
                "Finish Workout?",
                isPresented: isShowing { if case .unfinishedWithValues = $0 { true } else { false } },
                titleVisibility: .visible
            ) {
                Button("Complete Unfinished Sets") { state.finish(.complete) }
                    .accessibilityIdentifier("finish.complete")
                Button("Discard Unfinished Sets", role: .destructive) {
                    state.destructiveCount += 1
                    state.finish(.discard)
                }
                .accessibilityIdentifier("finish.discardUnfinished")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("finish.cancel")
            }
            .confirmationDialog(
                withoutValuesTitle,
                isPresented: isShowing { if case .unfinishedWithoutValues = $0 { true } else { false } },
                titleVisibility: .visible
            ) {
                Button("Finish Workout") { state.finish(.discard) }
                    .accessibilityIdentifier("finish.finish")
                Button("Keep Logging", role: .cancel) {}
                    .accessibilityIdentifier("finish.keepLogging")
            }
            // An alert, not a dialog: it is raised from the title menu, which is gone by then, so a popover's arrow would
            // have nothing to point at (the dialogs above are attached to the Finish button they come from).
            .alert(
                "Discard workout?",
                isPresented: $state.isDiscardConfirmationShown
            ) {
                Button("Discard Workout", role: .destructive) {
                    state.destructiveCount += 1
                    state.discardWorkout()
                }
                .accessibilityIdentifier("discard.confirm")
                Button("Keep Going", role: .cancel) {}
                    .accessibilityIdentifier("discard.keepGoing")
            } message: {
                Text("This workout and everything logged in it will be deleted. It cannot be undone.")
            }
            .sensoryFeedback(.warning, trigger: state.destructiveCount)
    }

    private var withoutValuesTitle: String {
        guard case .unfinishedWithoutValues(let count) = state.dialog else { return "" }
        return count == 1
            ? "1 set is not checked and will not be saved"
            : "\(count) sets are not checked and will not be saved"
    }

    /// A binding that is true while the current dialog satisfies `matches`; setting it false dismisses the dialog.
    private func isShowing(_ matches: @escaping (FinishDialog) -> Bool) -> Binding<Bool> {
        Binding(
            get: { state.dialog.map(matches) ?? false },
            set: { if !$0 { state.dialog = nil } }
        )
    }
}

private struct FinishFlowAlerts: ViewModifier {
    @Bindable var state: FinishFlowState

    func body(content: Content) -> some View {
        content
            .alert(
                "Could Not Finish",
                isPresented: Binding(
                    get: { state.errorMessage != nil },
                    set: { if !$0 { state.errorMessage = nil } }
                )
            ) {
                Button("Retry") { state.retryAfterError() }
                    .accessibilityIdentifier("finish.retry")
                Button("Dismiss", role: .cancel) {}
                    .accessibilityIdentifier("finish.dismiss")
            } message: {
                Text(state.errorMessage ?? "")
            }
            .alert(
                "Workout Saved",
                isPresented: Binding(get: { state.savedMessage != nil }, set: { _ in })
            ) {
                Button("OK") { state.acknowledgeSavedWithoutSummary() }
                    .accessibilityIdentifier("finish.savedOK")
            } message: {
                Text(state.savedMessage ?? "")
            }
    }
}
