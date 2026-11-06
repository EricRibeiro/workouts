import Testing

@testable import WorkoutsKit

@Suite("HeaderReveal")
struct HeaderRevealTests {
    @Test(arguments: [HeaderScrollPhase.interacting, .decelerating])
    func scrollEndStartsTimer(from phase: HeaderScrollPhase) {
        var state = HeaderRevealState()
        state.phaseChanged(from: phase, to: .idle)
        #expect(state.isRestorePending)
        #expect(!state.isPinned)
        #expect(state.generation == 1)
    }

    @Test func timerFireWithCurrentGenerationPins() {
        var state = HeaderRevealState()
        state.phaseChanged(from: .decelerating, to: .idle)
        let fired1 = state.restoreTimerFired(generation: state.generation)
        #expect(fired1)
        #expect(state.isPinned)
        #expect(!state.isRestorePending)
    }

    @Test func newScrollBeforeFireMakesTimerStale() {
        var state = HeaderRevealState()
        state.phaseChanged(from: .interacting, to: .idle)
        let stale = state.generation
        state.phaseChanged(from: .idle, to: .interacting)
        #expect(!state.isRestorePending)
        let fired2 = state.restoreTimerFired(generation: stale)
        #expect(!fired2)
        #expect(!state.isPinned)
    }

    @Test func secondScrollEndSupersedesFirstTimer() {
        var state = HeaderRevealState()
        state.phaseChanged(from: .interacting, to: .idle)
        let first = state.generation
        state.phaseChanged(from: .idle, to: .interacting)
        state.phaseChanged(from: .interacting, to: .idle)
        let fired3 = state.restoreTimerFired(generation: first)
        #expect(!fired3)
        let fired4 = state.restoreTimerFired(generation: state.generation)
        #expect(fired4)
        #expect(state.isPinned)
    }

    @Test func idleFromAnimatingOrTrackingDoesNothing() {
        for phase in [HeaderScrollPhase.animating, .tracking, .idle] {
            var state = HeaderRevealState()
            state.phaseChanged(from: phase, to: .idle)
            #expect(state == HeaderRevealState())
        }
    }

    @Test func scrollWhilePinnedUnpins() {
        var state = HeaderRevealState()
        state.phaseChanged(from: .decelerating, to: .idle)
        state.restoreTimerFired(generation: state.generation)
        #expect(state.isPinned)
        state.phaseChanged(from: .idle, to: .tracking)
        #expect(!state.isPinned)
        #expect(!state.isRestorePending)
    }

    @Test func firedTimerCannotFireTwice() {
        var state = HeaderRevealState()
        state.phaseChanged(from: .interacting, to: .idle)
        let generation = state.generation
        let fired5 = state.restoreTimerFired(generation: generation)
        #expect(fired5)
        let fired6 = state.restoreTimerFired(generation: generation)
        #expect(!fired6)
    }

    @Test func restoreDelayIsOneAndAHalfSeconds() {
        #expect(HeaderRevealState.restoreDelay == .milliseconds(1500))
    }
}
