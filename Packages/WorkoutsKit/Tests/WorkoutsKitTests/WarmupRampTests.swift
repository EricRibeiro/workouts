import Testing

@testable import WorkoutsKit

@Suite struct WarmupRampTests {
    private func ramp(
        _ weight: Double,
        _ unit: WeightUnit = .lb,
        _ bar: BarType = .olympic,
        custom: Double? = nil
    ) -> [WarmupStep] {
        WarmupRamp.steps(workingWeight: weight, unit: unit, barType: bar, customBarWeight: custom)
    }

    @Test func hundredPoundsOnTheOlympicBarDropsTheStepAtTheBar() {
        // 40% = 40 lb is not above the 45 lb bar.
        #expect(
            ramp(100) == [
                WarmupStep(weight: 45, reps: 10), WarmupStep(weight: 60, reps: 5), WarmupStep(weight: 80, reps: 3),
            ]
        )
    }

    @Test func aFullRamp() {
        #expect(
            ramp(200) == [
                WarmupStep(weight: 45, reps: 10), WarmupStep(weight: 80, reps: 8),
                WarmupStep(weight: 120, reps: 5), WarmupStep(weight: 160, reps: 3),
            ]
        )
    }

    @Test func aWorkingSetOnTheBarHasNoRamp() {
        #expect(ramp(45).isEmpty)
        #expect(ramp(40).isEmpty)
    }

    @Test func kilogramsUseTheMetricBarAndStep() {
        #expect(
            ramp(100, .kg) == [
                WarmupStep(weight: 20, reps: 10), WarmupStep(weight: 40, reps: 8),
                WarmupStep(weight: 60, reps: 5), WarmupStep(weight: 80, reps: 3),
            ]
        )
        // 40% = 20 kg is not above the bar; 60% = 30, 80% = 40.
        #expect(
            ramp(50, .kg) == [
                WarmupStep(weight: 20, reps: 10), WarmupStep(weight: 30, reps: 5), WarmupStep(weight: 40, reps: 3),
            ]
        )
        #expect(ramp(20, .kg).isEmpty)
    }

    @Test func stepsRoundToThePlateStep() {
        #expect(
            ramp(60, .lb, .ez) == [
                WarmupStep(weight: 15, reps: 10), WarmupStep(weight: 25, reps: 8),
                WarmupStep(weight: 35, reps: 5), WarmupStep(weight: 50, reps: 3),
            ]
        )
        #expect(ramp(52.5, .kg, .none).map(\.weight) == [20, 32.5, 42.5])
    }

    @Test func noBarHasNoEmptyBarStep() {
        #expect(
            ramp(100, .lb, .none) == [
                WarmupStep(weight: 40, reps: 8), WarmupStep(weight: 60, reps: 5), WarmupStep(weight: 80, reps: 3),
            ]
        )
    }

    @Test func customBarUsesItsOwnWeight() {
        #expect(ramp(135, .lb, .custom, custom: 35).map(\.weight) == [35, 55, 80, 110])
        #expect(ramp(135, .lb, .custom, custom: 35).map(\.reps) == [10, 8, 5, 3])
        // Unknown custom weight behaves as no bar.
        #expect(ramp(100, .lb, .custom, custom: nil) == ramp(100, .lb, .none))
        #expect(ramp(100, .lb, .custom, custom: -5) == ramp(100, .lb, .none))
    }

    @Test func aStepReachingTheWorkingWeightIsOmitted() {
        // Only the bar fits below 50 lb; 20, 30 and 40 are not above it.
        #expect(ramp(50) == [WarmupStep(weight: 45, reps: 10)])
        // 80% of 5 rounds to 5 itself.
        #expect(ramp(5, .lb, .none).isEmpty)
    }

    @Test func nothingForAMissingOrZeroWeight() {
        #expect(ramp(0).isEmpty)
        #expect(ramp(-10).isEmpty)
    }

    @Test func barWeightsAndPlateSteps() {
        #expect(WarmupRamp.barWeight(for: .olympic, unit: .lb, customWeight: nil) == 45)
        #expect(WarmupRamp.barWeight(for: .olympic, unit: .kg, customWeight: nil) == 20)
        #expect(WarmupRamp.barWeight(for: .ez, unit: .lb, customWeight: nil) == 15)
        #expect(WarmupRamp.barWeight(for: .ez, unit: .kg, customWeight: nil) == 7)
        #expect(WarmupRamp.barWeight(for: .none, unit: .lb, customWeight: 30) == 0)
        #expect(WarmupRamp.barWeight(for: .custom, unit: .kg, customWeight: 12) == 12)
        #expect(WarmupRamp.plateStep(for: .lb) == 5)
        #expect(WarmupRamp.plateStep(for: .kg) == 2.5)
    }
}
