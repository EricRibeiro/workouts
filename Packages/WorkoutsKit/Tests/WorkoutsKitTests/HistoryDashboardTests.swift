import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct HistoryDashboardTests {
    private static let toronto: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto") ?? .gmt
        return calendar
    }()

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
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
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
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
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

    @Test func recordTextByKind() {
        #expect(
            HistoryDashboard.text(for: PersonalRecord(kind: .e1rm, value: 116.7, weight: 100, reps: 5), unit: .kg)
                == "e1RM \(formatWeight(116.7)) kg"
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
        #expect(HistoryDashboard.groupedWeight(117.5) == "117.5")
        #expect(HistoryDashboard.groupedWeight(0) == "0")
    }
}
