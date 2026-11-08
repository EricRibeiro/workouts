import Foundation
import Testing

@testable import Workouts

@MainActor
struct SaveErrorsTests {
    private struct Failure: LocalizedError {
        var errorDescription: String? { "the disk is full" }
    }

    @Test func startsWithoutAMessage() {
        #expect(SaveErrors().message == nil)
    }

    @Test func reportSetsTheMessage() {
        let errors = SaveErrors()
        errors.report(Failure())
        #expect(errors.message == "Could not save: the disk is full.")
    }

    @Test func aLaterFailureReplacesTheMessage() {
        let errors = SaveErrors()
        errors.report(Failure())
        errors.report(CocoaError(.fileWriteOutOfSpace))
        #expect(errors.message?.hasPrefix("Could not save: ") == true)
        #expect(errors.message?.contains("the disk is full") == false)
    }

    @Test func reportKeepsTheRetryUntilAcknowledged() {
        var runs = 0
        let errors = SaveErrors()
        errors.report(Failure()) { runs += 1 }
        #expect(errors.retry != nil)
        errors.acknowledge(retrying: true)
        #expect(runs == 1)
        #expect(errors.message == nil)
        #expect(errors.retry == nil)
    }

    @Test func dismissingWithoutRetryDoesNotRunIt() {
        var runs = 0
        let errors = SaveErrors()
        errors.report(Failure()) { runs += 1 }
        errors.acknowledge()
        #expect(runs == 0)
        #expect(errors.retry == nil)
    }

    @Test func aReportWithoutARetryClearsTheOldOne() {
        let errors = SaveErrors()
        errors.report(Failure()) {}
        errors.report(Failure())
        #expect(errors.retry == nil)
    }

    @Test func deleteFailureMessageNamesTheCauseAndTheRecovery() {
        let text = DeleteFailure.message(for: Failure())
        #expect(text.contains("the disk is full"))
        #expect(text.contains("nothing is lost"))
    }
}
