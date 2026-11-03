import Testing

@testable import WorkoutsKit

struct BestSetTests {
    let kg = RecordsOptions()
    let lb = RecordsOptions(displayUnit: .lb)

    func best(_ sets: [LoggedSet], _ type: WeightType = .barbell, _ options: RecordsOptions = RecordsOptions())
        -> BestSet?
    {
        bestSet(in: sets, weightType: type, options: options)
    }

    @Test func noCountedSetIsNil() {
        #expect(best([]) == nil)
        #expect(
            best([LoggedSet(kind: .warmup, weight: 100, reps: 5), LoggedSet(weight: 100, reps: 5, completed: false)])
                == nil
        )
    }

    @Test func warmupAndUncheckedNeverWin() {
        let sets = [
            LoggedSet(kind: .warmup, weight: 200, reps: 5),
            LoggedSet(weight: 150, reps: 5, completed: false),
            LoggedSet(weight: 60, reps: 5),
        ]
        #expect(best(sets)?.index == 2)
    }

    @Test func strengthPicksHighestE1RMAndReportsIt() throws {
        let sets = [LoggedSet(weight: 100, reps: 5), LoggedSet(weight: 80, reps: 10)]
        let result = try #require(best(sets))
        // 100 x 5 = 116.67, 80 x 10 = 106.67
        #expect(result.index == 0)
        #expect(result.e1rm == 116.5)
        #expect(result.weightInDisplayUnit == 100)
        #expect(!result.lowConfidence)
    }

    @Test func strengthE1RMTieGoesToHeavierWeight() throws {
        // Epley: 90 x 10 = 120, 120 x 0 not allowed; use 1-rep 120 vs 90 x 10 (= 120).
        let sets = [LoggedSet(weight: 90, reps: 10), LoggedSet(weight: 120, reps: 1)]
        #expect(try #require(best(sets)).index == 1)
    }

    @Test func strengthTieOnE1RMAndWeightGoesToMoreReps() throws {
        // Same weight, same reps but different kind is the only way to tie e1RM and weight: tie then falls to earlier.
        let sets = [LoggedSet(kind: .drop, weight: 100, reps: 5), LoggedSet(weight: 100, reps: 5)]
        #expect(try #require(best(sets)).index == 0)
    }

    @Test func strengthTieOnE1RMAndWeightMoreRepsCannotDifferExceptViaConfidence() throws {
        // 12 reps vs 20 reps at the same weight: both clamp to 12 but 20 is low confidence, so 12 wins on confidence.
        let sets = [LoggedSet(weight: 50, reps: 20), LoggedSet(weight: 50, reps: 12)]
        let result = try #require(best(sets))
        #expect(result.index == 1)
        #expect(!result.lowConfidence)
    }

    @Test func strengthTieOnEverythingGoesToEarlierSet() throws {
        let sets = [LoggedSet(weight: 100, reps: 5), LoggedSet(weight: 100, reps: 5)]
        #expect(try #require(best(sets)).index == 0)
    }

    @Test func strengthWeightTieIsToleranceBased() throws {
        // 100 lb ties 45.359237 kg, so with equal reps the earlier set wins.
        let sets = [LoggedSet(weight: 100, unit: .lb, reps: 5), LoggedSet(weight: 45.359237, unit: .kg, reps: 5)]
        #expect(try #require(best(sets)).index == 0)
    }

    @Test func confidentFiftyByFiveBeatsLowConfidenceHundredByTwenty() throws {
        let sets = [LoggedSet(weight: 100, reps: 20), LoggedSet(weight: 50, reps: 5)]
        let result = try #require(best(sets))
        #expect(result.index == 1)
        #expect(!result.lowConfidence)
        #expect(result.e1rm == 58.5)
    }

    @Test func lowConfidenceBestReportsClampedValueForBothFormulas() throws {
        let sets = [LoggedSet(weight: 50, reps: 36)]
        let epley = try #require(best(sets, .barbell, kg))
        let brzycki = try #require(best(sets, .barbell, RecordsOptions(formula: .brzycki)))
        #expect(epley.e1rm == 70 && epley.lowConfidence)
        #expect(brzycki.e1rm == 72 && brzycki.lowConfidence)
    }

    @Test func betweenLowConfidenceSetsTheLargerWins() throws {
        let sets = [LoggedSet(weight: 50, reps: 36), LoggedSet(weight: 100, reps: 20)]
        let result = try #require(best(sets))
        #expect(result.index == 1)
        #expect(result.e1rm == 140)
    }

    @Test func strengthRequiresWeightAndRepsElseFallsBackToRepRule() throws {
        // No set has weight > 0 and reps >= 1: rep-type rule picks most reps, e1RM stays 0.
        let sets = [LoggedSet(weight: 0, reps: 8), LoggedSet(weight: nil, reps: 12), LoggedSet(weight: 100, reps: 0)]
        let result = try #require(best(sets))
        #expect(result.index == 1)
        #expect(result.e1rm == 0)
    }

    @Test func strengthFallbackOnTimedSession() throws {
        let sets = [LoggedSet(durationSeconds: 30), LoggedSet(durationSeconds: 45)]
        #expect(try #require(best(sets)).index == 1)
    }

    @Test func displayUnitConversionRoundsButOwnUnitIsExact() throws {
        let own = try #require(best([LoggedSet(weight: 17.25, unit: .lb, reps: 5)], .dumbbell, lb))
        #expect(own.weightInDisplayUnit == 17.25)
        let converted = try #require(best([LoggedSet(weight: 17.25, unit: .lb, reps: 5)], .dumbbell, kg))
        // 17.25 lb = 7.8245 kg -> 8.0
        #expect(converted.weightInDisplayUnit == 8)
        let otherWay = try #require(best([LoggedSet(weight: 20, unit: .kg, reps: 5)], .dumbbell, lb))
        #expect(otherWay.weightInDisplayUnit == 44)  // 44.09 -> 44.0
    }

    @Test func negativeWeightAndRepsClampToZero() {
        let sets = [LoggedSet(weight: -50, reps: 5), LoggedSet(weight: 50, reps: -5)]
        // Neither qualifies as strength; rep rule: only set 0 has reps... clamped to weight 0.
        #expect(best(sets)?.index == 0)
        #expect(best(sets)?.weightInDisplayUnit == 0)
    }

    // MARK: Rep types

    @Test func repTypePicksMostReps() throws {
        let sets = [LoggedSet(reps: 10), LoggedSet(reps: 15), LoggedSet(reps: 12)]
        let result = try #require(best(sets, .bodyweight))
        #expect(result.index == 1)
        #expect(result.e1rm == 0)
    }

    @Test func repTypeTieGoesToHeavierAddedWeight() throws {
        let sets = [LoggedSet(weight: 5, reps: 10), LoggedSet(weight: 10, reps: 10), LoggedSet(reps: 10)]
        let result = try #require(best(sets, .bodyweight))
        #expect(result.index == 1)
        #expect(result.weightInDisplayUnit == 10)
    }

    @Test func repTypeTieOnRepsAndWeightGoesToEarlierSet() throws {
        let sets = [LoggedSet(reps: 10), LoggedSet(reps: 10)]
        #expect(try #require(best(sets, .band)).index == 0)
    }

    @Test func timedLongestDurationWinsThenLongerDistance() throws {
        let sets = [
            LoggedSet(durationSeconds: 60, distanceMeters: 100),
            LoggedSet(durationSeconds: 90),
            LoggedSet(durationSeconds: 90, distanceMeters: 50),
        ]
        #expect(try #require(best(sets, .unweighted)).index == 2)
    }

    @Test func noDurationsFallsBackToLongestDistance() throws {
        let sets = [LoggedSet(distanceMeters: 200), LoggedSet(distanceMeters: 500), LoggedSet(distanceMeters: 300)]
        #expect(try #require(best(sets, .unweighted)).index == 1)
    }

    @Test func repsAlwaysBeatDurations() throws {
        let sets = [LoggedSet(durationSeconds: 600), LoggedSet(reps: 1, durationSeconds: 5)]
        #expect(try #require(best(sets, .unweighted)).index == 1)
    }

    @Test func countedSetsWithNothingMeasuredFallBackToFirstCounted() throws {
        let sets = [LoggedSet(kind: .warmup, reps: 5), LoggedSet(), LoggedSet()]
        #expect(try #require(best(sets, .bodyweight)).index == 1)
    }

    // MARK: Assisted

    @Test func upperMedianExamples() {
        #expect(upperMedian([4, 8, 8]) == 8)
        #expect(upperMedian([8, 4, 8]) == 8)
        #expect(upperMedian([1, 8]) == 8)
        #expect(upperMedian([8, 10]) == 10)
        #expect(upperMedian([7]) == 7)
        #expect(upperMedian([]) == nil)
    }

    @Test func assistedKeepsTypicalRepsThenPicksLowestAssistance() throws {
        // typical = upper median of [4,8,8] = 8; sets with >= 8 reps: index 1 (30 kg) and 2 (25 kg).
        let sets = [
            LoggedSet(weight: 10, reps: 4),
            LoggedSet(weight: 30, reps: 8),
            LoggedSet(weight: 25, reps: 8),
        ]
        let result = try #require(best(sets, .assisted))
        #expect(result.index == 2)
        #expect(result.e1rm == 0)
        #expect(result.weightInDisplayUnit == 25)
    }

    @Test func assistedUpperMedianExcludesLowRepSetEvenIfLessAssisted() throws {
        let sets = [LoggedSet(weight: 5, reps: 1), LoggedSet(weight: 30, reps: 8)]
        #expect(try #require(best(sets, .assisted)).index == 1)
    }

    @Test func assistedTieOnAssistanceGoesToMoreRepsThenEarlier() throws {
        let moreReps = [LoggedSet(weight: 20, reps: 8), LoggedSet(weight: 20, reps: 10)]
        // typical = upper median [8,10] = 10, only index 1 qualifies.
        #expect(try #require(best(moreReps, .assisted)).index == 1)
        let tied = [LoggedSet(weight: 20, reps: 8), LoggedSet(weight: 20, reps: 8)]
        #expect(try #require(best(tied, .assisted)).index == 0)
        let moreRepsSameAssist = [
            LoggedSet(weight: 20, reps: 8), LoggedSet(weight: 20, reps: 9), LoggedSet(weight: 20, reps: 9),
        ]
        // typical = sorted [8,9,9][1] = 9; both 9-rep sets tie on everything -> earlier (index 1).
        #expect(try #require(best(moreRepsSameAssist, .assisted)).index == 1)
    }

    @Test func assistedWithNoRepsUsesDurationRule() throws {
        let sets = [LoggedSet(weight: 20, durationSeconds: 30), LoggedSet(weight: 20, durationSeconds: 50)]
        #expect(try #require(best(sets, .assisted)).index == 1)
    }
}
