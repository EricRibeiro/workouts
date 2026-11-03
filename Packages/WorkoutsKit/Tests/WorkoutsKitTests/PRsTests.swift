import Foundation
import Testing

@testable import WorkoutsKit

struct PRsTests {
    let options = RecordsOptions()
    let exercise = UUID()

    func session(_ day: Double, _ sets: [LoggedSet], id: UUID = UUID()) -> Session {
        session(day, .barbell, sets, id: id)
    }

    func session(_ day: Double, _ type: WeightType, _ sets: [LoggedSet], id: UUID = UUID()) -> Session {
        Session(
            workoutID: id,
            time: Date(timeIntervalSince1970: day * 86_400),
            exerciseID: exercise,
            weightType: type,
            sets: sets
        )
    }

    func lb(_ weight: Double?, _ reps: Int?) -> LoggedSet { LoggedSet(weight: weight, unit: .lb, reps: reps) }

    func prs(_ history: [Session], _ current: Session, _ type: WeightType = .barbell) -> [PersonalRecord] {
        prsInSession(history: history, session: current, weightType: type, options: RecordsOptions(displayUnit: .lb))
    }

    @Test func firstBarbellSessionWithOneWorkingWeightSetsThreeKinds() {
        let result = prs([], session(1, [lb(100, 5), lb(100, 5)]))
        #expect(result.map(\.kind) == [.e1rm, .heaviest, .bestVolumeSet])
        #expect(result[0].value == 116.5)
        #expect(result[1].value == 100)
        #expect(result[2].value == 500)
    }

    @Test func firstSessionSetsRepsPRForLighterSetsButNotItsHeaviest() {
        let result = prs([], session(1, [lb(100, 5), lb(80, 10)]))
        #expect(result.map(\.kind) == [.e1rm, .heaviest, .bestVolumeSet, .repsAtWeight])
        #expect(result[3].weight == 80)
        #expect(result[3].reps == 10)
        #expect(result[3].value == 10)
    }

    @Test func heavierSingleAfterTenRepsIsOnlyHeaviest() {
        let result = prs([session(1, [lb(100, 10)])], session(2, [lb(105, 1)]))
        #expect(result.map(\.kind) == [.heaviest])
        #expect(result.first?.value == 105)
    }

    @Test func heavierTripleAndLighterTwelveReportsHeaviestAndRepsForTheTwelve() {
        // Eric's shorthand omits volume: the history here also holds a 60 x 25 set so 90 x 12 does not beat the volume.
        let result = prs([session(1, [lb(100, 10), lb(60, 25)])], session(2, [lb(110, 3), lb(90, 12)]))
        #expect(result.map(\.kind) == [.heaviest, .repsAtWeight])
        #expect(result[0].weight == 110)
        #expect(result[1].weight == 90)
        #expect(result[1].reps == 12)
    }

    @Test func moreRepsAtTheSameWeightIsARepsPR() {
        let result = prs([session(1, [lb(100, 10)])], session(2, [lb(100, 12)]))
        #expect(result.map(\.kind) == [.e1rm, .bestVolumeSet, .repsAtWeight])
        #expect(result.last?.reps == 12)
    }

    @Test func repsPRUsesDominance() {
        let history = [session(1, [lb(100, 10)])]
        #expect(prs(history, session(2, [lb(90, 10)])).isEmpty)
        #expect(prs(history, session(2, [lb(90, 11)])).map(\.kind) == [.repsAtWeight])
        #expect(prs(history, session(2, [lb(110, 3)])).map(\.kind) == [.heaviest])
    }

    @Test func equalIsNotAPR() {
        #expect(prs([session(1, [lb(100, 5)])], session(2, [lb(100, 5)])).isEmpty)
        let kg = prs([session(1, [lb(100, 5)])], session(2, [LoggedSet(weight: 45.359237, reps: 5)]))
        #expect(kg.isEmpty)
    }

    @Test func historyIsOnlyEntriesStrictlyBeforeTheSession() {
        let later = session(3, [lb(200, 5)])
        let sameTime = session(2, [lb(200, 5)])
        let current = session(2, [lb(100, 5)])
        let result = prs([later, sameTime], current)
        #expect(result.map(\.kind) == [.e1rm, .heaviest, .bestVolumeSet])
    }

    @Test func entryWithSameWorkoutAndExerciseIsIgnored() {
        let id = UUID()
        let old = session(1, [lb(200, 5)], id: id)
        let current = session(2, [lb(100, 5)], id: id)
        #expect(prs([old], current).map(\.kind) == [.e1rm, .heaviest, .bestVolumeSet])
        // A different workout at an earlier time still counts.
        #expect(prs([session(1, [lb(200, 5)])], current).isEmpty)
    }

    @Test func historyOrderIsIrrelevant() {
        let a = session(1, [lb(100, 10)])
        let b = session(2, [lb(110, 3)])
        let current = session(3, [lb(105, 3)])
        #expect(prs([a, b], current) == prs([b, a], current))
    }

    @Test func sessionOfOnlyWarmUpsOrUncheckedSetsSetsNothing() {
        let s = session(
            2,
            [
                LoggedSet(kind: .warmup, weight: 500, unit: .lb, reps: 10),
                LoggedSet(weight: 500, unit: .lb, reps: 10, completed: false),
            ]
        )
        #expect(prs([], s).isEmpty)
        #expect(prs([session(1, [lb(100, 5)])], s).isEmpty)
    }

    @Test func bodyweightAndBandHaveNoHeaviestWithoutAddedWeight() {
        for type in [WeightType.bodyweight, .band] {
            let result = prs([session(1, type, [LoggedSet(reps: 8)])], session(2, type, [LoggedSet(reps: 10)]), type)
            #expect(result.map(\.kind) == [.repsAtWeight])
            let first = prs([], session(1, type, [LoggedSet(reps: 8)]), type)
            #expect(first.map(\.kind) == [.repsAtWeight])
            let added = prs([session(1, type, [LoggedSet(reps: 8)])], session(2, type, [lb(10, 8)]), type)
            #expect(added.map(\.kind) == [.heaviest, .bestVolumeSet])
        }
    }

    @Test func plankLoggedAsOneRepAndSixtySecondsSetsDuration() {
        let plank = WeightType.unweighted
        let first = prs([], session(1, plank, [LoggedSet(reps: 1, durationSeconds: 60)]), plank)
        #expect(first.map(\.kind) == [.repsAtWeight, .longestDuration])
        #expect(first.last?.value == 60)
        let history = [session(1, plank, [LoggedSet(reps: 1, durationSeconds: 60)])]
        #expect(prs(history, session(2, plank, [LoggedSet(reps: 1, durationSeconds: 60)]), plank).isEmpty)
        let longer = prs(history, session(2, plank, [LoggedSet(reps: 1, durationSeconds: 75)]), plank)
        #expect(longer.map(\.kind) == [.longestDuration])
    }

    @Test func assistedPRsAreLeastAssistance() {
        let history = [session(1, .assisted, [LoggedSet(weight: 30, unit: .lb, reps: 8)])]
        let better = prs(history, session(2, .assisted, [LoggedSet(weight: 20, unit: .lb, reps: 5)]), .assisted)
        #expect(better.map(\.kind) == [.heaviest])
        #expect(better.first?.value == 20)
        // More assistance with fewer reps is dominated; more assistance with more reps is a reps PR.
        #expect(prs(history, session(2, .assisted, [LoggedSet(weight: 40, unit: .lb, reps: 6)]), .assisted).isEmpty)
        let reps = prs(history, session(2, .assisted, [LoggedSet(weight: 40, unit: .lb, reps: 9)]), .assisted)
        #expect(reps.map(\.kind) == [.repsAtWeight])
        #expect(
            prs([], session(1, .assisted, [LoggedSet(weight: 30, unit: .lb, reps: 8)]), .assisted).map(\.kind) == [
                .heaviest
            ]
        )
    }

    @Test func sessionCountsOnceForRepsUsingItsHeaviestQualifyingSet() {
        let history = [session(1, [lb(100, 10), lb(60, 25)])]
        let result = prs(history, session(2, [lb(80, 15), lb(90, 12), lb(95, 11)]))
        #expect(result.map(\.kind) == [.repsAtWeight])
        #expect(result.first?.weight == 95)
    }

    @Test func lowConfidenceE1RMNeverBeatsConfidentHistory() {
        let history = [session(1, [lb(100, 3)])]
        let result = prs(history, session(2, [lb(60, 25)]))
        #expect(!result.contains { $0.kind == .e1rm })
        let reverse = prs([session(1, [lb(100, 20)])], session(2, [lb(50, 5)]))
        #expect(reverse.contains { $0.kind == .e1rm })
    }
}
