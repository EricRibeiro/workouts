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

    @Test func heartRateTextRoundsToWholeBpm() {
        #expect(HistoryDashboard.heartRateText(127.6) == "128 bpm")
        #expect(HistoryDashboard.heartRateSpoken(126) == "126 beats per minute average")
    }

    // MARK: To-date baseline

    /// Weeks start Mon Oct 12, Oct 19, Oct 26, Nov 2 (and the current one, Nov 9).
    private var toDateEntries: [HistoryEntry] {
        [
            entry("First", at: date(2026, 10, 12, 7), minutes: 30, volume: 400),
            entry("Monday evening", at: date(2026, 10, 19, 20), minutes: 60, volume: 800),
            entry("Saturday", at: date(2026, 10, 31, 10), minutes: 90, volume: 1200),
            entry("Wednesday", at: date(2026, 11, 4, 12), minutes: 60, volume: 1600),
        ]
    }

    @Test func toDateBaselineOnAMondayMorningCountsOnlyTheEarlyHoursOfEachWeek() throws {
        let baseline = try #require(
            HistoryDashboard.toDateBaseline(entries: toDateEntries, calendar: Self.toronto, now: date(2026, 11, 9, 8))
        )
        #expect(baseline.weeks == 4)
        #expect(baseline.volume == 100)
        #expect(baseline.durationSeconds == 450)
        #expect(baseline.workouts == 0.25)
    }

    @Test func toDateBaselineOnAFridayEveningCountsThroughThatTimeAndNoLater() throws {
        let baseline = try #require(
            HistoryDashboard.toDateBaseline(entries: toDateEntries, calendar: Self.toronto, now: date(2026, 11, 13, 20))
        )
        // The Saturday workout is after the Friday cutoff and stays out.
        #expect(baseline.weeks == 4)
        #expect(baseline.volume == 700)
        #expect(baseline.durationSeconds == 2250)
        #expect(baseline.workouts == 0.75)
    }

    @Test func toDateBaselineLeavesOutALaterWorkoutOnTheSameWeekday() throws {
        let entries = [
            entry("Earlier", at: date(2026, 10, 28, 9), volume: 300),
            entry("Later", at: date(2026, 10, 28, 15), volume: 9000),
        ]
        let baseline = try #require(
            HistoryDashboard.toDateBaseline(entries: entries, calendar: Self.toronto, now: date(2026, 11, 4, 12))
        )
        #expect(baseline.weeks == 1)
        #expect(baseline.volume == 300)
        #expect(baseline.workouts == 1)
    }

    @Test func toDateBaselineIsNilInTheFirstWeekOfUseAndForNoWindow() {
        let thisWeek = [entry("Now", at: date(2026, 11, 9, 7))]
        #expect(
            HistoryDashboard.toDateBaseline(entries: thisWeek, calendar: Self.toronto, now: date(2026, 11, 11)) == nil
        )
        #expect(HistoryDashboard.toDateBaseline(entries: [], calendar: Self.toronto, now: date(2026, 11, 11)) == nil)
        #expect(
            HistoryDashboard.toDateBaseline(
                entries: toDateEntries,
                calendar: Self.toronto,
                now: date(2026, 11, 11),
                window: 0
            ) == nil
        )
    }

    @Test func toDateBaselineWithOnePriorWeekIsNotDividedByFour() throws {
        let entries = [entry("Last week", at: date(2026, 11, 2, 10), minutes: 40, volume: 600)]
        let baseline = try #require(
            HistoryDashboard.toDateBaseline(entries: entries, calendar: Self.toronto, now: date(2026, 11, 11, 12))
        )
        #expect(baseline.weeks == 1)
        #expect(baseline.volume == 600)
        #expect(baseline.durationSeconds == 2400)
        #expect(baseline.workouts == 1)
    }

    @Test func toDateBaselineCountsASkippedWeekAsZero() throws {
        let entries = [
            entry("Oct 19 week", at: date(2026, 10, 20, 12), volume: 400),
            entry("Nov 2 week", at: date(2026, 11, 3, 12), volume: 800),
        ]
        let baseline = try #require(
            HistoryDashboard.toDateBaseline(entries: entries, calendar: Self.toronto, now: date(2026, 11, 11, 12))
        )
        // Weeks of Nov 2, Oct 26 (nothing) and Oct 19; the week before the first workout is not counted.
        #expect(baseline.weeks == 3)
        #expect(baseline.volume == 400)
        #expect(baseline.workouts == 2.0 / 3.0)
    }

    @Test func toDateBaselineKeepsTheClockTimeAcrossADSTWeek() throws {
        // Clocks went back on Sun Nov 1, a 25-hour day: 23:00 on that Sunday is the same clock time as now.
        let entries = [
            entry("Monday", at: date(2026, 10, 26, 8), volume: 1000),
            entry("Sunday before", at: date(2026, 11, 1, 22, 30), volume: 500),
            entry("Sunday after", at: date(2026, 11, 1, 23, 30), volume: 7000),
        ]
        let baseline = try #require(
            HistoryDashboard.toDateBaseline(entries: entries, calendar: Self.toronto, now: date(2026, 11, 8, 23))
        )
        #expect(baseline.weeks == 1)
        #expect(baseline.volume == 1500)
        #expect(baseline.workouts == 2)
    }

    @Test func toDateBaselineCutsWeeksInTheCalendarsTimeZone() throws {
        // 19:00 to 21:00 Monday in Los Angeles is already Tuesday in UTC.
        func la(_ day: Int, _ hour: Int) -> Date { zonedDate(2026, 11, day, hour, 0, zone: "America/Los_Angeles") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        let entries = [entry("In", at: la(2, 19), volume: 1000), entry("Out", at: la(2, 21), volume: 5000)]
        let baseline = try #require(
            HistoryDashboard.toDateBaseline(entries: entries, calendar: calendar, now: la(9, 20))
        )
        #expect(baseline.weeks == 1)
        #expect(baseline.volume == 1000)
        #expect(baseline.workouts == 1)
    }

    // MARK: Volume axis

    private func axis(_ volumes: [Double], averages: [Double?] = []) -> VolumeAxis {
        HistoryDashboard.volumeAxis(totals: volumes.map { total(1, volume: $0) }, averages: averages)
    }

    @Test func volumeAxisReachesAnAverageAboveEveryBar() {
        let axis = axis([850, 120], averages: [nil, 2_400])
        #expect(axis.top == 2_500)
        #expect(axis.step == 500)
        #expect(axis.ticks == [0, 500, 1_000, 1_500, 2_000, 2_500])
    }

    @Test func volumeAxisKeepsFourToSixTicksAfterEightEmptyWeeks() {
        let volumes: [Double] = [3_000, 5_000, 4_000, 4_500] + Array(repeating: 0, count: 8)
        let averages = HistoryDashboard.trailingAverages(volumes, window: 4)
        let axis = axis(volumes, averages: averages)
        #expect(axis.top >= 5_000)
        #expect((4...6).contains(axis.ticks.count))
        #expect(axis.ticks.first == 0)
        #expect(axis.ticks.last == axis.top)
    }

    @Test func volumeAxisForTinyAndAwkwardVolumes() {
        #expect(axis([3]).ticks == [0, 1, 2, 3])
        #expect(axis([0.5]).ticks == [0, 1, 2, 3])
        #expect(axis([1_001]).ticks == [0, 250, 500, 750, 1_000, 1_250])
        #expect(axis([22_318, 5]).ticks == [0, 5_000, 10_000, 15_000, 20_000, 25_000])
        let empty = axis([0, 0])
        #expect(empty.top == 1 && empty.step == 1 && empty.ticks == [0, 1])
        #expect(axis([]).ticks == [0, 1])
    }

    @Test func volumeAxisHasFourToSixTicksAboveTheDataWithStepsOfAtLeastOne() {
        var highest = 0.5
        while highest < 2e9 {
            let result = axis([highest / 2], averages: [highest])
            #expect(result.top >= highest)
            #expect((4...6).contains(result.ticks.count))
            #expect(result.step >= 1)
            #expect(result.ticks.first == 0 && result.ticks.last == result.top)
            highest *= 1.07
        }
    }

    @Test func volumeAxisThinnedKeepsTheTopAndCountsDownFromIt() {
        let result = axis([22_318])
        #expect(result.thinned(every: 2) == [5_000, 15_000, 25_000])
        #expect(result.thinned(every: 1) == result.ticks)
        #expect(axis([3]).thinned(every: 2) == [1, 3])
        #expect(axis([0]).thinned(every: 2) == [1])
    }

    // MARK: Hero text

    private let heroWeek = ThisWeekSummary(workouts: 1, durationSeconds: 2_400, volume: 22_318, unit: .lb)

    @Test func heroTextReadsTheWeekAgainstWhatIsUsualByNow() {
        let usual = WeekToDate(volume: 18_400, durationSeconds: 2_100, workouts: 1, weeks: 4)
        let text = HistoryDashboard.heroText(week: heroWeek, goal: 3, toDate: usual)
        #expect(text.countText == "1")
        #expect(text.goalText == "of 3 workouts")
        #expect(text.volumeText == "22,318 lb")
        #expect(text.durationText == "40min")
        #expect(text.usualVolumeText == "18,400 lb")
        #expect(text.usualDurationText == "35min")
        #expect(
            text.spoken
                == "This week, 1 of 3 workouts, 40 minutes, 22,318 lb, usually 18,400 lb and 35 minutes by now"
        )
    }

    @Test func heroTextUsesTheSingularForAGoalOfOne() {
        let text = HistoryDashboard.heroText(week: heroWeek, goal: 1, toDate: nil)
        #expect(text.goalText == "of 1 workout")
        #expect(text.spoken.hasPrefix("This week, 1 of 1 workout, 40 minutes"))
    }

    @Test func heroTextForAnEmptyWeekShowsZeroes() {
        let empty = ThisWeekSummary(workouts: 0, durationSeconds: 0, volume: 0, unit: .lb)
        let text = HistoryDashboard.heroText(week: empty, goal: 3, toDate: nil)
        #expect(text.countText == "0")
        #expect(text.volumeText == "0 lb")
        #expect(text.durationText == "0min")
        #expect(text.spoken == "This week, 0 of 3 workouts")
    }

    @Test func heroTextWithoutABaselineHasNoUsualFigures() {
        let text = HistoryDashboard.heroText(week: heroWeek, goal: 3, toDate: nil)
        #expect(text.usualVolumeText == nil)
        #expect(text.usualDurationText == nil)
        #expect(text.spoken == "This week, 1 of 3 workouts, 40 minutes, 22,318 lb")
    }

    @Test func heroTextDropsAZeroBaselineFigure() {
        let noVolume = WeekToDate(volume: 0, durationSeconds: 2_100, workouts: 1, weeks: 2)
        let first = HistoryDashboard.heroText(week: heroWeek, goal: 3, toDate: noVolume)
        #expect(first.usualVolumeText == nil)
        #expect(first.usualDurationText == "35min")
        #expect(first.spoken.hasSuffix("22,318 lb, usually 35 minutes by now"))

        let zero = WeekToDate(volume: 0, durationSeconds: 0, workouts: 0, weeks: 2)
        let second = HistoryDashboard.heroText(week: heroWeek, goal: 3, toDate: zero)
        #expect(second.usualVolumeText == nil && second.usualDurationText == nil)
        #expect(second.spoken == "This week, 1 of 3 workouts, 40 minutes, 22,318 lb")
    }
}
