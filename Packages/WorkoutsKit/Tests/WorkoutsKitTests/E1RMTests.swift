import Testing

@testable import WorkoutsKit

struct E1RMTests {
    @Test func epleyBasic() {
        let estimate = e1rm(weight: 100, reps: 5, formula: .epley)
        #expect(abs(estimate.value - 100 * (1 + 5.0 / 30)) < 1e-9)
        #expect(!estimate.lowConfidence)
    }

    @Test func brzyckiBasic() {
        let estimate = e1rm(weight: 100, reps: 5, formula: .brzycki)
        #expect(abs(estimate.value - 100 * 36 / 32) < 1e-9)
    }

    @Test func fiftyByThirtySixClampsAtTwelve() {
        let epley = e1rm(weight: 50, reps: 36, formula: .epley)
        let brzycki = e1rm(weight: 50, reps: 36, formula: .brzycki)
        #expect(epley.value == 70)
        #expect(brzycki.value == 72)
        #expect(epley.lowConfidence && brzycki.lowConfidence)
    }

    @Test func hundredByTwentyClampsAtTwelve() {
        #expect(e1rm(weight: 100, reps: 20, formula: .epley).value == 140)
        #expect(e1rm(weight: 100, reps: 20, formula: .brzycki).value == 144)
    }

    @Test func twelveRepsIsConfidentThirteenIsNot() {
        #expect(!e1rm(weight: 100, reps: 12, formula: .epley).lowConfidence)
        #expect(e1rm(weight: 100, reps: 13, formula: .epley).lowConfidence)
    }

    @Test func oneRepIsTheWeightForBothFormulas() {
        #expect(e1rm(weight: 82.5, reps: 1, formula: .epley) == E1RMEstimate(value: 82.5, lowConfidence: false))
        #expect(e1rm(weight: 82.5, reps: 1, formula: .brzycki) == E1RMEstimate(value: 82.5, lowConfidence: false))
    }

    @Test func zeroRepsOrNonPositiveWeightIsZero() {
        #expect(e1rm(weight: 100, reps: 0, formula: .epley).value == 0)
        #expect(e1rm(weight: 0, reps: 5, formula: .epley).value == 0)
        #expect(e1rm(weight: -5, reps: 5, formula: .brzycki).value == 0)
        #expect(!e1rm(weight: 0, reps: 50, formula: .epley).lowConfidence)
    }

    @Test func brzyckiNeverDividesByZeroAtOrAbove37Reps() {
        let at37 = e1rm(weight: 50, reps: 37, formula: .brzycki)
        let at100 = e1rm(weight: 50, reps: 100, formula: .brzycki)
        #expect(at37.value == 72 && at100.value == 72)
        #expect(at37.lowConfidence)
    }

    @Test func confidentBeatsLowConfidenceHoweverLarge() {
        let confident = e1rm(weight: 50, reps: 5, formula: .epley)
        let low = e1rm(weight: 100, reps: 20, formula: .epley)
        #expect(confident.value < low.value)
        #expect(betterE1RM(confident, low))
        #expect(!betterE1RM(low, confident))
    }

    @Test func largerWinsWithinSameConfidence() {
        let small = E1RMEstimate(value: 60, lowConfidence: true)
        let large = E1RMEstimate(value: 70, lowConfidence: true)
        #expect(betterE1RM(large, small))
        #expect(!betterE1RM(small, large))
        #expect(!betterE1RM(large, large))
        #expect(
            betterE1RM(E1RMEstimate(value: 90, lowConfidence: false), E1RMEstimate(value: 80, lowConfidence: false))
        )
    }
}
