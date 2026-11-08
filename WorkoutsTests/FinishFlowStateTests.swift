import Foundation
import Testing
import WorkoutsKit

@testable import Workouts

/// R3W-3: Finish can save the workout and then fail while building the summary. The engine has let go of the workout by
/// then, so the Finish button (and any alert on it) is gone; the state must surface the failure on its own and end up
/// closing the cover.
@MainActor
struct FinishFlowStateTests {
    private struct Failure: LocalizedError {
        var errorDescription: String? { "the fetch failed" }
    }

    @Test func aSummaryFailureAfterTheSaveSaysSavedAndClosesTheCover() {
        let state = FinishFlowState()
        var discards = 0
        var finishes = 0
        state.configure(onFinished: { _ in finishes += 1 }, onDiscarded: { discards += 1 })

        state.run(finish: { throw Failure() }, isWorkoutGone: { true }, retry: {})

        #expect(state.errorMessage == nil)
        #expect(state.savedMessage?.contains("saved") == true)
        #expect(state.savedMessage?.contains("the fetch failed") == true)
        #expect(discards == 0 && finishes == 0)

        state.acknowledgeSavedWithoutSummary()
        #expect(state.savedMessage == nil)
        #expect(discards == 1)
        #expect(finishes == 0)
    }

    /// R4W-1: the saved-without-summary hand-off carries the workout id so Health and the template question still run.
    @Test func aSummaryFailureHandsTheSavedWorkoutOnWithoutASummary() {
        let state = FinishFlowState()
        let id = UUID()
        var saved: [UUID?] = []
        var discards = 0
        state.configure(
            onFinished: { _ in },
            onDiscarded: { discards += 1 },
            onSavedWithoutSummary: { saved.append($0) }
        )

        state.run(finish: { throw Failure() }, isWorkoutGone: { true }, retry: {}, workoutID: id)
        #expect(saved.isEmpty)

        state.acknowledgeSavedWithoutSummary()
        #expect(saved == [id])
        #expect(discards == 0)
    }

    @Test func aFailedSaveKeepsTheWorkoutAndOffersRetry() {
        let state = FinishFlowState()
        var discards = 0
        var retries = 0
        state.configure(onFinished: { _ in }, onDiscarded: { discards += 1 })

        state.run(finish: { throw Failure() }, isWorkoutGone: { false }, retry: { retries += 1 })

        #expect(state.savedMessage == nil)
        #expect(state.errorMessage?.contains("nothing is lost") == true)
        #expect(discards == 0)

        state.retryAfterError()
        #expect(retries == 1)
    }
}
