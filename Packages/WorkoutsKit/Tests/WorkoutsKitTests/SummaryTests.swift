import Foundation
import Testing

@testable import WorkoutsKit

struct SummaryTests {
    func session(_ type: WeightType, _ sets: [LoggedSet]) -> Session {
        Session(
            workoutID: UUID(),
            time: Date(timeIntervalSince1970: 0),
            exerciseID: UUID(),
            weightType: type,
            sets: sets
        )
    }

    @Test func setCountIncludesWarmupsWorkingDoesNot() {
        let s = session(
            .barbell,
            [
                LoggedSet(kind: .warmup, weight: 40, reps: 10),
                LoggedSet(weight: 100, reps: 5),
                LoggedSet(kind: .drop, weight: 80, reps: 8),
                LoggedSet(weight: 100, reps: 5, completed: false),
            ]
        )
        let summary = summarize(s, options: RecordsOptions())
        #expect(summary.setCount == 3)
        #expect(summary.working == 2)
        #expect(summary.totalReps == 13)
        #expect(summary.volume == 1140)
        #expect(summary.best?.index == 1)
    }

    @Test func emptySessionHasNoBestAndZeros() {
        let summary = summarize(session(.barbell, []), options: RecordsOptions())
        #expect(summary == SessionSummary(best: nil, volume: 0, totalReps: 0, setCount: 0, working: 0))
    }

    @Test func onlyWarmupsOrUncheckedSetsHaveNoBest() {
        let s = session(
            .barbell,
            [LoggedSet(kind: .warmup, weight: 40, reps: 10), LoggedSet(weight: 100, reps: 5, completed: false)]
        )
        let summary = summarize(s, options: RecordsOptions())
        #expect(summary.best == nil)
        #expect(summary.setCount == 1)
        #expect(summary.working == 0)
        #expect(summary.totalReps == 0)
    }

    @Test func assistedSummaryHasZeroVolumeButReps() {
        let s = session(.assisted, [LoggedSet(weight: 30, reps: 8), LoggedSet(weight: 25, reps: 8)])
        let summary = summarize(s, options: RecordsOptions())
        #expect(summary.volume == 0)
        #expect(summary.totalReps == 16)
        #expect(summary.best?.index == 1)
    }

    @Test func summaryHonoursDisplayUnit() {
        let s = session(.barbell, [LoggedSet(weight: 100, unit: .lb, reps: 5)])
        let summary = summarize(s, options: RecordsOptions(displayUnit: .kg))
        #expect(summary.volume == 227)
        #expect(summary.best?.weightInDisplayUnit == 45.5)  // 45.359 -> 45.5
        #expect(summary.best?.set.weight == 100)
    }
}
