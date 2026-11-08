import Testing

@testable import WorkoutsKit

struct VolumeTests {
    @Test func strengthSumsCountedSets() {
        let sets = [
            LoggedSet(kind: .warmup, weight: 20, reps: 10),
            LoggedSet(weight: 100, reps: 5),
            LoggedSet(kind: .drop, weight: 80, reps: 5),
            LoggedSet(kind: .failure, weight: 60, reps: 5),
            LoggedSet(weight: 100, reps: 5, completed: false),
        ]
        #expect(volume(of: sets, weightType: .barbell, displayUnit: .kg) == 1200)
    }

    @Test func convertsToDisplayUnitAndRoundsToHalf() {
        let sets = [LoggedSet(weight: 100, unit: .lb, reps: 5)]
        #expect(volume(of: sets, weightType: .barbell, displayUnit: .lb) == 500)
        #expect(volume(of: sets, weightType: .barbell, displayUnit: .kg) == 227)  // 226.796
        let kgSets = [LoggedSet(weight: 20, unit: .kg, reps: 5)]
        #expect(volume(of: kgSets, weightType: .barbell, displayUnit: .lb) == 220.5)  // 220.46
    }

    @Test func volumeKgIsUnroundedAndDisplayedVolumeRoundsOnce() {
        let sets = [LoggedSet(weight: 11, unit: .kg, reps: 1)]
        #expect(volumeKg(of: sets, weightType: .barbell) == 11)
        #expect(volumeKg(of: sets, weightType: .assisted) == 0)
        #expect(displayedVolume(kg: 33, displayUnit: .lb) == 73)  // 72.75
        #expect(displayedVolume(kg: 11, displayUnit: .lb) == 24.5)  // 24.25 rounds half up
    }

    @Test func mixedUnitsSumInKg() {
        let sets = [LoggedSet(weight: 100, unit: .lb, reps: 10), LoggedSet(weight: 50, unit: .kg, reps: 10)]
        #expect(volume(of: sets, weightType: .machine, displayUnit: .kg) == 953.5)  // 453.59 + 500
    }

    @Test func bodyweightWithoutWeightIsZeroButAddedWeightCounts() {
        #expect(volume(of: [LoggedSet(reps: 20)], weightType: .bodyweight, displayUnit: .kg) == 0)
        #expect(volume(of: [LoggedSet(weight: 10, reps: 5)], weightType: .bodyweight, displayUnit: .kg) == 50)
    }

    @Test func assistedVolumeIsZero() {
        #expect(volume(of: [LoggedSet(weight: 30, reps: 10)], weightType: .assisted, displayUnit: .kg) == 0)
    }

    @Test func timedSetsAddNothing() {
        let sets = [LoggedSet(weight: 20, durationSeconds: 60), LoggedSet(distanceMeters: 500)]
        #expect(volume(of: sets, weightType: .weighted, displayUnit: .kg) == 0)
    }

    @Test func negativeValuesClampToZero() {
        let sets = [LoggedSet(weight: -50, reps: 5), LoggedSet(weight: 50, reps: -5)]
        #expect(volume(of: sets, weightType: .barbell, displayUnit: .kg) == 0)
    }
}
