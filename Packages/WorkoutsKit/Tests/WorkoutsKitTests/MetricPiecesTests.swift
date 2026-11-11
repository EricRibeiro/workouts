import Testing

@testable import WorkoutsKit

@Suite struct MetricPiecesTests {
    private func pieces(_ text: String) -> [MetricPiece] { MetricPieces.split(text) }

    @Test func valueWithUnitDropsTheSpace() {
        #expect(
            pieces("14,569 lb") == [MetricPiece(text: "14,569", isUnit: false), MetricPiece(text: "lb", isUnit: true)]
        )
    }

    @Test func aWordAfterAUnitJoinsItWithItsSpace() {
        #expect(
            pieces("10 All Out") == [
                MetricPiece(text: "10", isUnit: false),
                MetricPiece(text: "All Out", isUnit: true),
            ]
        )
        #expect(
            pieces("128 bpm") == [MetricPiece(text: "128", isUnit: false), MetricPiece(text: "bpm", isUnit: true)]
        )
        #expect(
            pieces("342 kcal") == [MetricPiece(text: "342", isUnit: false), MetricPiece(text: "kcal", isUnit: true)]
        )
    }

    @Test func glued() {
        #expect(pieces("40min") == [MetricPiece(text: "40", isUnit: false), MetricPiece(text: "min", isUnit: true)])
    }

    @Test func compoundDurationKeepsTheSpaceBeforeANumber() {
        #expect(
            pieces("1h 5min") == [
                MetricPiece(text: "1", isUnit: false), MetricPiece(text: "h", isUnit: true),
                MetricPiece(text: " 5", isUnit: false), MetricPiece(text: "min", isUnit: true),
            ]
        )
    }

    @Test func paceUnitFollowsThePunctuation() {
        #expect(
            pieces("5'30''/km") == [MetricPiece(text: "5'30''/", isUnit: false), MetricPiece(text: "km", isUnit: true)]
        )
    }

    @Test func noLettersIsOnePlainPiece() {
        #expect(pieces("1 / 3") == [MetricPiece(text: "1 / 3", isUnit: false)])
    }

    @Test func aLabelBeforeTheNumberIsPlain() {
        #expect(
            pieces("e1RM 235 lb") == [
                MetricPiece(text: "e1RM 235", isUnit: false), MetricPiece(text: "lb", isUnit: true),
            ]
        )
    }

    @Test func plainTextAndEmpty() {
        #expect(pieces("Push") == [MetricPiece(text: "Push", isUnit: false)])
        #expect(pieces("") == [])
    }
}
