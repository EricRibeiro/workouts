import Foundation
import Testing

@testable import WorkoutsKit

struct ChartSeriesTests {
    let options = RecordsOptions()
    let exercise = UUID()

    func session(_ day: Double, _ type: WeightType, _ sets: [LoggedSet], id: UUID = UUID()) -> Session {
        Session(
            workoutID: id,
            time: Date(timeIntervalSince1970: day * 86_400),
            exerciseID: exercise,
            weightType: type,
            sets: sets
        )
    }

    @Test func oneStablySortedPointPerSession() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let sessions = [
            session(3, .barbell, [LoggedSet(weight: 100, reps: 5)], id: c),
            session(1, .barbell, [LoggedSet(weight: 100, reps: 5)], id: a),
            session(1, .barbell, [LoggedSet(weight: 90, reps: 5)], id: b),
        ]
        let points = chartSeries(sessions, metric: .totalReps, options: options)
        #expect(points.map(\.workoutID) == [a, b, c])
        #expect(points.map(\.value) == [5, 5, 5])
    }

    @Test func rowsOfOneExerciseInOneWorkoutAreOnePoint() {
        let workout = UUID()
        let other = UUID()
        let sessions = [
            session(1, .barbell, [LoggedSet(weight: 100, reps: 5), LoggedSet(weight: 100, reps: 5)], id: workout),
            session(1, .barbell, [LoggedSet(weight: 80, reps: 10), LoggedSet(weight: 80, reps: 10)], id: workout),
            session(2, .barbell, [LoggedSet(weight: 90, reps: 5)], id: other),
        ]
        let reps = chartSeries(sessions, metric: .totalReps, options: options)
        #expect(reps.map(\.workoutID) == [workout, other])
        #expect(reps.map(\.value) == [30, 5])  // 10 + 20, not two points
        let volumes = chartSeries(sessions, metric: .volume, options: options)
        #expect(volumes.map(\.value) == [2600, 450])  // 1000 + 1600
        #expect(chartSeries(sessions, metric: .maxWeight, options: options).map(\.value) == [100, 90])
        #expect(chartSeries(sessions, metric: .bestReps, options: options).map(\.value) == [10, 5])
        #expect(chartSeries(sessions, metric: .e1rm, options: options).count == 2)
    }

    @Test func sessionWithoutCountedSetWithRepsHasNoPointForAnyMetric() {
        let sessions = [
            session(1, .barbell, [LoggedSet(kind: .warmup, weight: 60, reps: 10)]),
            session(2, .barbell, [LoggedSet(weight: 100, reps: 5, completed: false)]),
            session(3, .barbell, [LoggedSet(weight: 100, reps: 0)]),
            session(4, .barbell, [LoggedSet(durationSeconds: 60)]),
        ]
        for metric in ChartMetric.allCases {
            #expect(chartSeries(sessions, metric: metric, options: options).isEmpty)
        }
    }

    @Test func e1rmUsesBestSetAndFlagsLowConfidence() {
        let sessions = [
            session(1, .barbell, [LoggedSet(weight: 100, reps: 5), LoggedSet(weight: 80, reps: 8)]),
            session(2, .barbell, [LoggedSet(weight: 100, reps: 20)]),
        ]
        let points = chartSeries(sessions, metric: .e1rm, options: options)
        #expect(points.map(\.value) == [116.5, 140])  // 116.67 -> 116.5; 100 * (1 + 12/30)
        #expect(points.map(\.lowConfidence) == [false, true])
    }

    @Test func confidentE1RMBeatsLargerLowConfidenceWithinSession() {
        let sets = [LoggedSet(weight: 100, reps: 20), LoggedSet(weight: 50, reps: 5)]
        let points = chartSeries([session(1, .barbell, sets)], metric: .e1rm, options: options)
        #expect(points.first?.value == 58.5)  // 58.33
        #expect(points.first?.lowConfidence == false)
    }

    @Test func unweightedSetDoesNotHideLowConfidenceE1RM() {
        let sets = [LoggedSet(weight: 100, reps: 15), LoggedSet(reps: 5)]
        let points = chartSeries([session(1, .barbell, sets)], metric: .e1rm, options: options)
        #expect(points.map(\.value) == [140])  // 100 * (1 + 12/30): reps clamp at 12
        #expect(points.first?.lowConfidence == true)
        let later = sets + [LoggedSet(weight: 50, reps: 15)]
        #expect(chartSeries([session(1, .barbell, later)], metric: .e1rm, options: options).map(\.value) == [140])
    }

    @Test func e1rmDoesNotApplyToRepTypesAndAssisted() {
        let sets = [LoggedSet(weight: 10, reps: 5)]
        for type in [WeightType.bodyweight, .unweighted, .band, .assisted] {
            #expect(chartSeries([session(1, type, sets)], metric: .e1rm, options: options).isEmpty)
        }
    }

    @Test func unloadedStrengthSessionHasNoE1RMOrMaxWeightPoint() {
        let s = session(1, .machine, [LoggedSet(reps: 10)])
        #expect(chartSeries([s], metric: .e1rm, options: options).isEmpty)
        #expect(chartSeries([s], metric: .maxWeight, options: options).isEmpty)
        #expect(chartSeries([s], metric: .totalReps, options: options).map(\.value) == [10])
        #expect(chartSeries([s], metric: .volume, options: options).map(\.value) == [0])
    }

    @Test func maxWeightIsHeaviestCountedSetWithRepsInDisplayUnit() {
        let sets = [
            LoggedSet(kind: .warmup, weight: 200, reps: 5),
            LoggedSet(weight: 100, unit: .lb, reps: 5),
            LoggedSet(weight: 150, reps: 0),
            LoggedSet(weight: 40, reps: 5),
        ]
        let kg = chartSeries([session(1, .barbell, sets)], metric: .maxWeight, options: options)
        #expect(kg.map(\.value) == [45.5])  // 100 lb = 45.36 kg -> 45.5
        let lb = chartSeries(
            [session(1, .barbell, sets)],
            metric: .maxWeight,
            options: RecordsOptions(displayUnit: .lb)
        )
        #expect(lb.map(\.value) == [100])  // as entered
    }

    @Test func assistedMaxWeightIsLowestAssistance() {
        let sets = [LoggedSet(weight: 40, reps: 5), LoggedSet(weight: 20, reps: 5), LoggedSet(weight: 30, reps: 5)]
        let points = chartSeries([session(1, .assisted, sets)], metric: .maxWeight, options: options)
        #expect(points.map(\.value) == [20])
        let zero = [LoggedSet(weight: 0, reps: 5), LoggedSet(weight: 10, reps: 5)]
        #expect(chartSeries([session(1, .assisted, zero)], metric: .maxWeight, options: options).map(\.value) == [0])
    }

    @Test func unloadedRepTypeMaxWeightHasNoPointButRepsMetricsDo() {
        let s = session(1, .bodyweight, [LoggedSet(reps: 12), LoggedSet(reps: 8)])
        #expect(chartSeries([s], metric: .maxWeight, options: options).isEmpty)
        #expect(chartSeries([s], metric: .totalReps, options: options).map(\.value) == [20])
        #expect(chartSeries([s], metric: .bestReps, options: options).map(\.value) == [12])
        let weighted = session(1, .bodyweight, [LoggedSet(weight: 10, reps: 8), LoggedSet(reps: 12)])
        #expect(chartSeries([weighted], metric: .maxWeight, options: options).map(\.value) == [10])
    }

    @Test func volumeDoesNotApplyToAssisted() {
        let s = session(1, .assisted, [LoggedSet(weight: 20, reps: 5)])
        #expect(chartSeries([s], metric: .volume, options: options).isEmpty)
        #expect(chartSeries([s], metric: .totalReps, options: options).map(\.value) == [5])
    }

    @Test func volumeAndRepMetricsIgnoreWarmUps() {
        let sets = [
            LoggedSet(kind: .warmup, weight: 60, reps: 10),
            LoggedSet(weight: 100, reps: 5),
            LoggedSet(kind: .drop, weight: 80, reps: 8),
        ]
        let s = session(1, .barbell, sets)
        #expect(chartSeries([s], metric: .volume, options: options).map(\.value) == [1140])
        #expect(chartSeries([s], metric: .totalReps, options: options).map(\.value) == [13])
        #expect(chartSeries([s], metric: .bestReps, options: options).map(\.value) == [8])
    }
}
