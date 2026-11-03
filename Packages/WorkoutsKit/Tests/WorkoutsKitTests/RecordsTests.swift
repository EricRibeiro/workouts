import Foundation
import Testing

@testable import WorkoutsKit

struct RecordsTests {
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

    func record(_ kind: RecordKind, _ all: [ExerciseRecord]) -> ExerciseRecord? {
        all.first { $0.kind == kind }
    }

    @Test func emptyHistoryHasNoRecords() {
        #expect(records([], weightType: .barbell, options: options).isEmpty)
    }

    @Test func strengthRecordsComeFromTheBestSets() {
        let id = UUID()
        let s = session(1, [LoggedSet(weight: 100, reps: 5), LoggedSet(weight: 80, reps: 10)], id: id)
        let all = records([s], weightType: .barbell, options: options)
        let e1 = record(.e1rm, all)
        #expect(e1?.value == 116.5)  // 100 x 5 = 116.67; 80 x 10 = 106.67
        #expect(e1?.weight == 100)
        #expect(e1?.reps == 5)
        #expect(e1?.workoutID == id)
        #expect(record(.heaviest, all)?.value == 100)
        #expect(record(.bestVolumeSet, all)?.value == 800)  // 80 x 10, not session volume
        #expect(record(.bestVolumeSet, all)?.reps == 10)
        #expect(record(.longestDuration, all) == nil)
    }

    @Test func recordOrderIsKindsThenRepsRowsHeaviestFirst() {
        let s = session(
            1,
            [LoggedSet(weight: 80, reps: 10), LoggedSet(weight: 100, reps: 5), LoggedSet(durationSeconds: 5)]
        )
        let all = records([s], weightType: .barbell, options: options)
        #expect(
            all.map(\.kind) == [
                .e1rm, .heaviest, .bestVolumeSet, .longestDuration, .repsAtWeight, .repsAtWeight,
            ]
        )
        #expect(all.filter { $0.kind == .repsAtWeight }.map(\.weight) == [100, 80])
    }

    @Test func inputOrderIsIrrelevant() {
        let a = session(1, [LoggedSet(weight: 100, reps: 5)])
        let b = session(2, [LoggedSet(weight: 110, reps: 3)])
        let c = session(3, [LoggedSet(weight: 90, reps: 12)])
        let forward = records([a, b, c], weightType: .barbell, options: options)
        #expect(forward == records([c, a, b], weightType: .barbell, options: options))
        #expect(forward == records([b, c, a], weightType: .barbell, options: options))
    }

    @Test func earlierSessionKeepsATie() {
        let first = UUID()
        let second = UUID()
        let sets = [LoggedSet(weight: 100, reps: 5)]
        let all = records(
            [session(2, sets, id: second), session(1, sets, id: first)],
            weightType: .barbell,
            options: options
        )
        for kind in [RecordKind.e1rm, .heaviest, .bestVolumeSet, .repsAtWeight] {
            #expect(record(kind, all)?.workoutID == first)
        }
    }

    @Test func tieWithinToleranceAcrossUnitsKeepsEarlier() {
        let first = UUID()
        let all = records(
            [
                session(1, [LoggedSet(weight: 100, unit: .lb, reps: 5)], id: first),
                session(2, [LoggedSet(weight: 45.359237, unit: .kg, reps: 5)]),
            ],
            weightType: .barbell,
            options: options
        )
        #expect(all.filter { $0.kind == .repsAtWeight }.count == 1)
        #expect(all.allSatisfy { $0.workoutID == first })
    }

    @Test func confidentE1RMRecordBeatsLowConfidenceOne() {
        let confident = UUID()
        let all = records(
            [
                session(1, [LoggedSet(weight: 100, reps: 20)]),
                session(2, [LoggedSet(weight: 50, reps: 5)], id: confident),
            ],
            weightType: .barbell,
            options: options
        )
        let e1 = record(.e1rm, all)
        #expect(e1?.workoutID == confident)
        #expect(e1?.value == 58.5)
        #expect(e1?.lowConfidence == false)
    }

    @Test func lowConfidenceRecordIsHeldWhenNothingConfidentExists() {
        let all = records([session(1, [LoggedSet(weight: 100, reps: 20)])], weightType: .barbell, options: options)
        #expect(record(.e1rm, all)?.value == 140)
        #expect(record(.e1rm, all)?.lowConfidence == true)
    }

    @Test func warmUpsAndUncheckedSetsSetNothing() {
        let s = session(
            1,
            [LoggedSet(kind: .warmup, weight: 60, reps: 10), LoggedSet(weight: 100, reps: 5, completed: false)]
        )
        #expect(records([s], weightType: .barbell, options: options).isEmpty)
    }

    @Test func repTypesHaveHeaviestAndVolumeOnlyWithAddedWeight() {
        for type in [WeightType.bodyweight, .band, .unweighted] {
            let plain = records([session(1, type, [LoggedSet(reps: 12)])], weightType: type, options: options)
            #expect(plain.map(\.kind) == [.repsAtWeight])
            let added = records(
                [session(1, type, [LoggedSet(weight: 10, reps: 8), LoggedSet(reps: 12)])],
                weightType: type,
                options: options
            )
            #expect(added.map(\.kind) == [.heaviest, .bestVolumeSet, .repsAtWeight, .repsAtWeight])
            #expect(record(.e1rm, added) == nil)
        }
    }

    @Test func assistedHeaviestIsLeastAssistanceAndRowsGoLeastFirst() {
        let sets = [LoggedSet(weight: 30, reps: 5), LoggedSet(weight: 20, reps: 4), LoggedSet(weight: 40, reps: 8)]
        let all = records([session(1, .assisted, sets)], weightType: .assisted, options: options)
        #expect(record(.heaviest, all)?.value == 20)
        #expect(record(.e1rm, all) == nil)
        #expect(record(.bestVolumeSet, all) == nil)
        #expect(all.filter { $0.kind == .repsAtWeight }.map(\.weight) == [20, 30, 40])
        let later = records(
            [session(1, .assisted, sets), session(2, .assisted, [LoggedSet(weight: 10, reps: 1)])],
            weightType: .assisted,
            options: options
        )
        #expect(record(.heaviest, later)?.value == 10)
    }

    @Test func plankLoggedAsOneRepAndSixtySecondsSetsLongestDuration() {
        let sets = [LoggedSet(reps: 1, durationSeconds: 60), LoggedSet(durationSeconds: 45)]
        let all = records([session(1, .unweighted, sets)], weightType: .unweighted, options: options)
        let duration = record(.longestDuration, all)
        #expect(duration?.value == 60)
        #expect(duration?.durationSeconds == 60)
        #expect(duration?.reps == 1)
    }

    @Test func repsAtWeightKeepsBestRepsPerWeightWithEarliestHolder() {
        let first = UUID()
        let second = UUID()
        let all = records(
            [
                session(1, [LoggedSet(weight: 100, reps: 8)], id: first),
                session(2, [LoggedSet(weight: 100, reps: 8), LoggedSet(weight: 100, reps: 10)], id: second),
            ],
            weightType: .barbell,
            options: options
        )
        let rows = all.filter { $0.kind == .repsAtWeight }
        #expect(rows.count == 1)
        #expect(rows.first?.reps == 10)
        #expect(rows.first?.workoutID == second)
    }

    @Test func inSessionTiesPreferHeavierThenMoreReps() {
        let volumeTie = session(2, [LoggedSet(weight: 50, reps: 10), LoggedSet(weight: 100, reps: 5)])
        let volume = records([volumeTie], weightType: .barbell, options: options)
        #expect(record(.bestVolumeSet, volume)?.weight == 100)  // 500 either way: heavier weight wins
        let heaviestTie = session(3, [LoggedSet(weight: 100, reps: 3), LoggedSet(weight: 100, reps: 6)])
        #expect(record(.heaviest, records([heaviestTie], weightType: .barbell, options: options))?.reps == 6)
    }

    @Test func displayUnitConvertsHeldWeights() {
        let s = session(1, [LoggedSet(weight: 100, unit: .lb, reps: 5)])
        let lb = records([s], weightType: .barbell, options: RecordsOptions(displayUnit: .lb))
        #expect(record(.heaviest, lb)?.value == 100)
        let kg = records([s], weightType: .barbell, options: options)
        #expect(record(.heaviest, kg)?.value == 45.5)
    }
}
