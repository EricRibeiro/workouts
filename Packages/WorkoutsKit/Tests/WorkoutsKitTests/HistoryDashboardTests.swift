import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct HistoryDashboardTests {
    private static let toronto = TestSupport.torontoCalendar

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return Self.toronto.date(from: parts) ?? .distantPast
    }

    private func entry(_ name: String, at start: Date, minutes: Int = 60, volume: Double = 1000) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            name: name,
            startedAt: start,
            durationSeconds: minutes * 60,
            volume: volume,
            unit: .lb,
            prCount: 0,
            exerciseNames: []
        )
    }

    // MARK: This week

    @Test func thisWeekSumsTheMondayFirstWeek() {
        // Tue 2026-11-03 is "now"; the week is Mon Nov 2 to Sun Nov 8.
        let entries = [
            entry("Mon", at: date(2026, 11, 2, 0, 30), minutes: 30, volume: 500),
            entry("Tue", at: date(2026, 11, 3, 9), minutes: 45, volume: 700.25),
            entry("Sun before", at: date(2026, 11, 1, 23, 30), minutes: 90, volume: 9000),
            entry("Older", at: date(2026, 10, 20)),
        ]
        let week = HistoryDashboard.thisWeek(entries: entries, calendar: Self.toronto, now: date(2026, 11, 3))
        #expect(week.workouts == 2)
        #expect(week.durationSeconds == 75 * 60)
        #expect(week.volume == 1200.5)
        #expect(week.unit == .lb)
    }

    /// Three workouts of 0.2 kg remainder (100.2 kg each, shown as 100.0 per row) total 300.6 kg: the card shows the
    /// single-rounded 300.5, not the 300.0 that summing the rounded rows gives.
    @Test func thisWeekRoundsTheUnroundedKgTotalOnce() {
        let rows = (0..<3).map { index in
            HistoryEntry(
                id: UUID(),
                name: "W\(index)",
                startedAt: date(2026, 11, 2 + index),
                durationSeconds: 60,
                volume: displayedVolume(kg: 100.2, displayUnit: .kg),
                volumeKg: 100.2,
                unit: .kg,
                prCount: 0,
                exerciseNames: []
            )
        }
        #expect(rows.allSatisfy { $0.volume == 100 })
        let week = HistoryDashboard.thisWeek(entries: rows, calendar: Self.toronto, now: date(2026, 11, 4))
        #expect(week.volume == 300.5)
    }

    @Test func thisWeekIgnoresALocaleThatStartsOnSunday() {
        var sunday = Self.toronto
        sunday.firstWeekday = 1
        let entries = [entry("Sun", at: date(2026, 11, 1, 10))]
        // Sunday Nov 1 belongs to the week of Oct 26 (Monday first), not to the one containing Tue Nov 3.
        let week = HistoryDashboard.thisWeek(entries: entries, calendar: sunday, now: date(2026, 11, 3))
        #expect(week.workouts == 0)
    }

    @Test func emptyWeekIsZeroInTheFallbackUnit() {
        let week = HistoryDashboard.thisWeek(
            entries: [],
            calendar: Self.toronto,
            now: date(2026, 11, 3),
            unit: .kg
        )
        #expect(week == ThisWeekSummary(workouts: 0, durationSeconds: 0, volume: 0, unit: .kg))
    }

    // MARK: Last workout

    @Test func lastWorkoutIsTheNewest() {
        let entries = [
            entry("a", at: date(2026, 10, 1)), entry("b", at: date(2026, 11, 1)), entry("c", at: date(2026, 9, 1)),
        ]
        #expect(HistoryDashboard.lastWorkout(entries: entries)?.name == "b")
        #expect(HistoryDashboard.lastWorkout(entries: []) == nil)
    }

    // MARK: Recent PRs

    @MainActor
    private func build(
        _ context: ModelContext,
        _ specs: [(name: String, exercise: UUID, exerciseName: String, at: Date, weight: Double, finished: Bool)]
    ) -> [Workout] {
        specs.map { spec in
            let workout = Workout(
                name: spec.name,
                startedAt: spec.at,
                finishedAt: spec.finished ? spec.at.addingTimeInterval(45 * 60) : nil
            )
            let row = WorkoutExercise(
                exerciseID: spec.exercise,
                exerciseName: spec.exerciseName,
                unit: .kg,
                workout: workout
            )
            let set = WorkoutSet(kind: .normal, weight: spec.weight, reps: 5, completed: true, workoutExercise: row)
            context.insert(workout)
            context.insert(row)
            context.insert(set)
            return workout
        }
    }

    @MainActor
    @Test func recentPRsAreNewestFirstWithNamesAndValues() throws {
        let container = try makeTestContainer()
        let bench = UUID()
        let squat = UUID()
        let workouts = build(
            container.mainContext,
            [
                ("A", bench, "Bench Press", date(2026, 10, 1), 100, true),
                ("B", bench, "Bench Press", date(2026, 10, 8), 100, true),  // equal: no PR
                ("C", squat, "Squat", date(2026, 10, 10), 140, true),
                ("D", bench, "Bench Press", date(2026, 10, 15), 110, true),
                ("Running", bench, "Bench Press", date(2026, 10, 20), 200, false),
            ]
        )
        try container.mainContext.save()

        let prs = HistoryDashboard.recentPRs(
            from: workouts,
            weightType: { _ in .barbell },
            options: RecordsOptions(displayUnit: .kg),
            limit: 3
        )
        #expect(prs.map(\.exerciseName) == ["Bench Press", "Squat", "Bench Press"])
        #expect(prs.map(\.date) == [date(2026, 10, 15), date(2026, 10, 10), date(2026, 10, 1)])
        #expect(prs[0].kind == .e1rm)
        #expect(prs[0].text.hasPrefix("e1RM "))
        #expect(prs[0].text.hasSuffix(" kg"))
        #expect(prs[0].recordCount >= 1)
        #expect(prs[0].sentence.hasPrefix("Bench Press, e1RM"))
        // One row per exercise session.
        #expect(Set(prs.map(\.id)).count == prs.count)
    }

    @MainActor
    @Test func recentPRsHonourTheLimitAndAnEmptyHistory() throws {
        let container = try makeTestContainer()
        let bench = UUID()
        let workouts = build(
            container.mainContext,
            [
                ("A", bench, "Bench Press", date(2026, 10, 1), 100, true),
                ("B", bench, "Bench Press", date(2026, 10, 8), 105, true),
            ]
        )
        try container.mainContext.save()
        let options = RecordsOptions(displayUnit: .kg)
        #expect(
            HistoryDashboard.recentPRs(from: workouts, weightType: { _ in .barbell }, options: options, limit: 1).count
                == 1
        )
        #expect(
            HistoryDashboard.recentPRs(from: workouts, weightType: { _ in .barbell }, options: options, limit: 0)
                .isEmpty
        )
        #expect(HistoryDashboard.recentPRs(from: [], weightType: { _ in nil }, options: options).isEmpty)
    }

    @MainActor
    @Test func buildEqualsTheTwoSeparateCalls() throws {
        let container = try makeTestContainer()
        let bench = UUID()
        let squat = UUID()
        let workouts = build(
            container.mainContext,
            [
                ("A", bench, "Bench Press", date(2026, 10, 1), 100, true),
                ("B", bench, "Bench Press", date(2026, 10, 8), 100, true),
                ("C", squat, "Squat", date(2026, 10, 10), 140, true),
                ("D", bench, "Bench Press", date(2026, 10, 15), 110, true),
                ("Running", bench, "Bench Press", date(2026, 10, 20), 200, false),
            ]
        )
        try container.mainContext.save()
        let options = RecordsOptions(displayUnit: .lb)

        let summary = HistoryDashboard.build(from: workouts, weightType: { _ in .barbell }, options: options)
        let entries = HistoryList.entries(from: workouts, weightType: { _ in .barbell }, options: options)
        let prs = HistoryDashboard.recentPRs(from: workouts, weightType: { _ in .barbell }, options: options)
        #expect(!summary.recentPRs.isEmpty)
        #expect(summary.entries.contains { $0.prCount > 0 })
        #expect(summary.entries.count == 4)
        #expect(summary.entries == entries)
        #expect(summary.recentPRs == prs)

        let limited = HistoryDashboard.build(from: workouts, weightType: { _ in .barbell }, options: options, limit: 1)
        #expect(limited.recentPRs == Array(prs.prefix(1)))
        #expect(limited.entries == entries)
        #expect(
            HistoryDashboard.build(from: [], weightType: { _ in nil }, options: options)
                == HistorySummary(entries: [], recentPRs: [])
        )
    }

    @Test func recordTextByKind() {
        #expect(
            HistoryDashboard.text(for: PersonalRecord(kind: .e1rm, value: 116.7, weight: 100, reps: 5), unit: .kg)
                == "e1RM \(WeightFormat.number(116.7)) kg"
        )
        #expect(
            HistoryDashboard.text(for: PersonalRecord(kind: .heaviest, value: 100, weight: 100, reps: 5), unit: .kg)
                == "100 kg × 5"
        )
        #expect(
            HistoryDashboard.text(for: PersonalRecord(kind: .longestDuration, value: 45, weight: 0, reps: 0), unit: .lb)
                == "45 s"
        )
    }

    @Test func recordTextGroupsThousands() {
        #expect(
            HistoryDashboard.text(for: PersonalRecord(kind: .e1rm, value: 1929, weight: 1500, reps: 3), unit: .lb)
                == "e1RM 1,929 lb"
        )
        #expect(
            HistoryDashboard.text(for: PersonalRecord(kind: .heaviest, value: 1250, weight: 1250, reps: 2), unit: .lb)
                == "1,250 lb × 2"
        )
    }

    @MainActor
    @Test func weekAverageHeartRateIsDurationWeightedAndHidesWhenNone() throws {
        let context = try makeTestContext()
        func workout(_ start: Date, minutes: Int, bpm: Double?, finished: Bool = true) -> Workout {
            makeWorkout(in: context, startedAt: start, minutes: finished ? minutes : nil, avgHeartRate: bpm)
        }
        // Tue Nov 3 is "now"; the week is Mon Nov 2 to Sun Nov 8.
        let now = date(2026, 11, 3)
        let calendar = Self.toronto
        let none = [
            workout(date(2026, 11, 3), minutes: 40, bpm: nil),
            workout(date(2026, 11, 1, 23), minutes: 60, bpm: 170),
        ]
        #expect(HistoryDashboard.weekAverageHeartRate(workouts: [], calendar: calendar, now: now) == nil)
        #expect(HistoryDashboard.weekAverageHeartRate(workouts: none, calendar: calendar, now: now) == nil)
        let some =
            none + [
                workout(date(2026, 11, 2, 8), minutes: 30, bpm: 120),
                workout(date(2026, 11, 3, 9), minutes: 90, bpm: 140),
                workout(date(2026, 11, 4), minutes: 60, bpm: 200, finished: false),
            ]
        // (120 x 30 + 140 x 90) / 120 = 135: the unfinished, out-of-week and HR-less workouts are ignored.
        let average = try #require(HistoryDashboard.weekAverageHeartRate(workouts: some, calendar: calendar, now: now))
        #expect(abs(average - 135) < 0.0001)
    }

    // MARK: Weekly totals

    private func zonedDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, zone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: parts) ?? .distantPast
    }

    private func total(_ workouts: Int, volume: Double = 0, seconds: Int = 0) -> WeekTotal {
        WeekTotal(weekStart: .distantPast, workouts: workouts, durationSeconds: seconds, volume: volume)
    }

    @Test func weeklyTotalsZeroFillOldestFirst() {
        let entries = [
            entry("This", at: date(2026, 11, 3), minutes: 30, volume: 500),
            entry("This 2", at: date(2026, 11, 4), minutes: 45, volume: 700),
            entry("Two back", at: date(2026, 10, 20), minutes: 60, volume: 1000),
            entry("Too old", at: date(2026, 9, 1)),
        ]
        let totals = HistoryDashboard.weeklyTotals(
            entries: entries,
            weeks: 4,
            calendar: Self.toronto,
            now: date(2026, 11, 4)
        )
        #expect(
            totals.map(\.weekStart) == [
                date(2026, 10, 12, 0), date(2026, 10, 19, 0), date(2026, 10, 26, 0), date(2026, 11, 2, 0),
            ]
        )
        #expect(totals.map(\.workouts) == [0, 1, 0, 2])
        #expect(totals.map(\.durationSeconds) == [0, 3600, 0, 75 * 60])
        #expect(totals.map(\.volume) == [0, 1000, 0, 1200])
        #expect(HistoryDashboard.weeklyTotals(entries: entries, weeks: 0, calendar: Self.toronto, now: .now).isEmpty)
    }

    @Test func weeklyTotalsSplitSundayNightFromMondayMorningInTheCalendarsZone() {
        let zone = "America/Toronto"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        let sunday = entry("Sun", at: zonedDate(2026, 11, 1, 23, 30, zone: zone), volume: 100)
        let monday = entry("Mon", at: zonedDate(2026, 11, 2, 0, 30, zone: zone), volume: 200)
        let now = zonedDate(2026, 11, 3, 9, 0, zone: zone)
        let totals = HistoryDashboard.weeklyTotals(entries: [sunday, monday], weeks: 2, calendar: calendar, now: now)
        #expect(totals.map(\.workouts) == [1, 1])
        #expect(totals.map(\.volume) == [100, 200])
    }

    @Test func weeklyTotalsKeepEveryWeekMidnightMondayAcrossADSTChange() {
        // DST ended Sunday 2026-11-01 in America/Toronto: the week of 10-26 has 169 hours.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto") ?? .gmt
        let now = zonedDate(2026, 11, 3, 9, 0, zone: "America/Toronto")
        let totals = HistoryDashboard.weeklyTotals(entries: [], weeks: 4, calendar: calendar, now: now)
        #expect(totals.count == 4)
        #expect(totals.allSatisfy { calendar.component(.hour, from: $0.weekStart) == 0 })
        #expect(totals.allSatisfy { calendar.component(.weekday, from: $0.weekStart) == 2 })
        #expect(totals[2].weekStart == zonedDate(2026, 10, 26, 0, 0, zone: "America/Toronto"))
    }

    @Test func trailingAveragesLeaveTheValueItselfOut() {
        let averages = HistoryDashboard.trailingAverages([10, 20, 30, 40, 1000], window: 2)
        #expect(averages == [nil, nil, 15, 25, 35])
    }

    @Test func trailingAveragesNeedAFullWindowAndAPositiveSize() {
        #expect(HistoryDashboard.trailingAverages([1, 2], window: 4) == [nil, nil])
        #expect(HistoryDashboard.trailingAverages([1, 2, 3], window: 0) == [nil, nil, nil])
        #expect(HistoryDashboard.trailingAverages([1, 2, 3], window: -1) == [nil, nil, nil])
        #expect(HistoryDashboard.trailingAverages([], window: 2).isEmpty)
    }

    @Test func baselineIsTheMeanOfTheWeeksBeforeTheCurrentOne() throws {
        let totals = [
            total(9, volume: 9999), total(2, volume: 1000, seconds: 3600), total(3, volume: 2000, seconds: 7200),
            total(0), total(3, volume: 3000, seconds: 3600), total(1, volume: 1, seconds: 60),
        ]
        let baseline = try #require(HistoryDashboard.baseline(totals: totals, window: 4))
        #expect(baseline.volume == 1500)
        #expect(baseline.durationSeconds == 3600)
        #expect(baseline.workouts == 2)
    }

    @Test func baselineIsNilWithTooFewWeeksOrNoWorkouts() {
        #expect(HistoryDashboard.baseline(totals: []) == nil)
        #expect(HistoryDashboard.baseline(totals: [total(1), total(1), total(1), total(1)]) == nil)
        #expect(
            HistoryDashboard.baseline(totals: [total(0), total(0), total(0), total(0), total(5, volume: 100)]) == nil
        )
        #expect(HistoryDashboard.baseline(totals: [total(1), total(1)], window: 0) == nil)
        #expect(HistoryDashboard.baseline(totals: [total(1), total(1), total(1), total(1), total(1)]) != nil)
    }

    @Test func volumeAxisIsThreeToFiveEqualNiceSteps() {
        func axis(_ volumes: [Double]) -> (top: Double, step: Double) {
            let totals = volumes.map { total(1, volume: $0) }
            return (HistoryDashboard.volumeAxisTop(totals: totals), HistoryDashboard.volumeAxisStep(totals: totals))
        }
        #expect(axis([]) == (1, 1))
        #expect(axis([0, 0]) == (1, 1))
        // 4 x 250 and 5 x 200 tie on 1,000: the count nearest 4 wins.
        #expect(axis([850, 120]) == (1_000, 250))
        #expect(axis([1_001]) == (1_250, 250))
        #expect(axis([22_318, 5]) == (25_000, 5_000))
        #expect(axis([25_100]) == (30_000, 10_000))
        #expect(axis([100_000]) == (100_000, 25_000))
        #expect(axis([3_100]) == (4_000, 1_000))
        #expect(axis([5_000.5]) == (6_000, 2_000))
    }

    @Test func volumeAxisNeverFallsShortOfTheBusiestWeekAndKeepsItsStepCount() {
        for busiest in stride(from: 1.0, through: 400_000, by: 733.7) {
            let totals = [total(1, volume: busiest)]
            let top = HistoryDashboard.volumeAxisTop(totals: totals)
            let step = HistoryDashboard.volumeAxisStep(totals: totals)
            let count = (top / step).rounded()
            #expect(top >= busiest)
            #expect(abs(top / step - count) < 1e-9 && (3...5).contains(Int(count)))
        }
    }

    @Test func heartRateTextRoundsToWholeBpm() {
        #expect(HistoryDashboard.heartRateText(127.6) == "128 bpm")
        #expect(HistoryDashboard.heartRateSpoken(126) == "126 beats per minute average")
    }
}
