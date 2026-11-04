import Foundation
import Testing

@testable import WorkoutsKit

struct ExerciseHistoryTests {
    let exercise = UUID()
    let options = RecordsOptions(formula: .epley, displayUnit: .kg)

    func session(_ day: Double, _ sets: [LoggedSet], id: UUID = UUID()) -> Session {
        Session(
            workoutID: id,
            time: Date(timeIntervalSince1970: day * 86_400),
            exerciseID: exercise,
            weightType: .barbell,
            sets: sets
        )
    }

    @Test func newestFirstWithNamesAndFallback() {
        let a = UUID()
        let b = UUID()
        let result = ExerciseHistory.sessions(
            [
                session(1, [LoggedSet(weight: 100, reps: 5)], id: a),
                session(2, [LoggedSet(weight: 100, reps: 5)], id: b),
            ],
            names: [a: "Push"],
            weightType: .barbell,
            options: options
        )
        #expect(result.map(\.workoutID) == [b, a])
        #expect(result.map(\.workoutName) == ["Workout", "Push"])
    }

    @Test func completedSetsOnlyAndMarkersDoNotConsumeNumbers() throws {
        let result = ExerciseHistory.sessions(
            [
                session(
                    1,
                    [
                        LoggedSet(kind: .warmup, weight: 60, reps: 8),
                        LoggedSet(weight: 100, reps: 5),
                        LoggedSet(weight: 100, reps: 4, completed: false),
                        LoggedSet(kind: .drop, weight: 80, reps: 8),
                        LoggedSet(weight: 100, reps: 5),
                        LoggedSet(kind: .failure, weight: 100, reps: 3),
                    ]
                )
            ],
            names: [:],
            weightType: .barbell,
            options: options
        )
        let sets = try #require(result.first).sets
        #expect(sets.map(\.label) == ["W", "1", "D", "2", "F"])
        #expect(sets.map(\.text) == ["60 kg × 8", "100 kg × 5", "80 kg × 8", "100 kg × 5", "100 kg × 3"])
    }

    @Test func weightsStayInTheSessionsOwnUnit() throws {
        let result = ExerciseHistory.sessions(
            [session(1, [LoggedSet(weight: 225, unit: .lb, reps: 5)])],
            names: [:],
            weightType: .barbell,
            options: options
        )
        #expect(try #require(result.first).sets.first?.text == "225 lb × 5")
    }

    @Test func prTrophyOnTheRecordSettingSetOnly() throws {
        let first = session(1, [LoggedSet(weight: 100, reps: 5), LoggedSet(weight: 80, reps: 5)])
        let second = session(2, [LoggedSet(weight: 100, reps: 5), LoggedSet(weight: 110, reps: 5)])
        let result = ExerciseHistory.sessions([first, second], names: [:], weightType: .barbell, options: options)
        let newest = try #require(result.first)
        #expect(newest.workoutID == second.workoutID)
        #expect(newest.sets.map(\.isPR) == [false, true])
        #expect(newest.prCount > 0)
        let oldest = try #require(result.last)
        #expect(oldest.sets.first?.isPR == true)
    }

    @Test func sessionWithoutCompletedSetsIsLeftOut() {
        let result = ExerciseHistory.sessions(
            [session(1, [LoggedSet(weight: 100, reps: 5, completed: false)])],
            names: [:],
            weightType: .barbell,
            options: options
        )
        #expect(result.isEmpty)
    }

    @Test func repeatedExerciseInOneWorkoutGetsDistinctIds() {
        let id = UUID()
        let result = ExerciseHistory.sessions(
            [
                session(1, [LoggedSet(weight: 100, reps: 5)], id: id),
                session(1, [LoggedSet(weight: 100, reps: 5)], id: id),
            ],
            names: [:],
            weightType: .barbell,
            options: options
        )
        #expect(Set(result.map(\.id)).count == 2)
    }

    @Test func durationSetReadsAsTime() throws {
        let result = ExerciseHistory.sessions(
            [session(1, [LoggedSet(durationSeconds: 45)])],
            names: [:],
            weightType: .barbell,
            options: options
        )
        #expect(try #require(result.first).sets.first?.text == "45 s")
    }
}

struct ChartConfigTests {
    @Test func metricsAndDefaultsByCategory() {
        #expect(ChartMetric.available(for: .strength) == [.e1rm, .maxWeight, .volume, .totalReps, .bestReps])
        #expect(ChartMetric.available(for: .repBased) == [.bestReps, .totalReps, .maxWeight, .volume])
        #expect(ChartMetric.available(for: .assisted) == [.maxWeight, .bestReps, .totalReps])
        #expect(ChartMetric.defaultMetric(for: .strength) == .e1rm)
        #expect(ChartMetric.defaultMetric(for: .repBased) == .bestReps)
        #expect(ChartMetric.defaultMetric(for: .assisted) == .maxWeight)
    }

    @Test func titlesAndWeightValued() {
        #expect(ChartMetric.maxWeight.title(for: .assisted) == "Least assistance")
        #expect(ChartMetric.maxWeight.title(for: .strength) == "Max weight")
        #expect(ChartMetric.e1rm.title(for: .strength) == "Est. 1RM")
        #expect(ChartMetric.volume.isWeightValued)
        #expect(!ChartMetric.totalReps.isWeightValued)
    }

    @Test func rangesCutFromNow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let day: TimeInterval = 86_400
        let points = [0, 20, 60, 120, 200, 400].map {
            ChartPoint(workoutID: UUID(), time: now.addingTimeInterval(-Double($0) * day), value: 1)
        }
        #expect(ChartRange.month.filter(points, now: now, calendar: calendar).count == 2)
        #expect(ChartRange.threeMonths.filter(points, now: now, calendar: calendar).count == 3)
        #expect(ChartRange.sixMonths.filter(points, now: now, calendar: calendar).count == 4)
        #expect(ChartRange.year.filter(points, now: now, calendar: calendar).count == 5)
        #expect(ChartRange.all.filter(points, now: now, calendar: calendar).count == 6)
        #expect(ChartRange.standard == .threeMonths)
    }
}
