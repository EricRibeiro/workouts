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
    fileprivate var errorMessage: String?
    /// Counts confirmed destructive choices; drives the `.warning` haptic.
    fileprivate var destructiveCount = 0

    private var engine: ActiveWorkoutEngine?
    private var onFinished: (FinishSummary) -> Void = { _ in }
    private var onDiscarded: () -> Void = {}
    /// What "Retry" in the error alert repeats.
    private var retry: (() -> Void)?

    /// Tap on Finish: asks the engine which dialog applies and shows it, or finishes at once when every set is checked.
    func begin(
        engine: ActiveWorkoutEngine,
        onFinished: @escaping (FinishSummary) -> Void,
        onDiscarded: @escaping () -> Void
    ) {
        self.engine = engine
        self.onFinished = onFinished
        self.onDiscarded = onDiscarded
        do {
            let dialog = try engine.finishSummary().dialog
            if dialog == .none {
                finish(.discard)
            } else {
                self.dialog = dialog
            }
        } catch {
            fail(error) { [weak self] in
                self?.begin(engine: engine, onFinished: onFinished, onDiscarded: onDiscarded)
            }
        }
    }

    fileprivate func finish(_ unfinished: UnfinishedSets) {
        guard let engine else { return }
        do {
            let summary = try engine.finish(unfinished: unfinished)
            onFinished(summary)
        } catch {
            fail(error) { [weak self] in self?.finish(unfinished) }
        }
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

    fileprivate func retryAfterError() {
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
    /// Presents the Finish confirmation dialogs and the failure alert driven by `state`.
    func finishFlow(_ state: FinishFlowState) -> some View {
        modifier(FinishFlow(state: state))
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
