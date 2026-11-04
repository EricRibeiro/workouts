import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct HistoryListTests {
    private static let toronto: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto") ?? .gmt
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return Self.toronto.date(from: parts) ?? .distantPast
    }

    private func entry(
        _ name: String,
        at start: Date,
        pr: Int = 0,
        exercises: [String] = [],
        volume: Double = 1000
    ) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            name: name,
            startedAt: start,
            durationSeconds: 3600,
            volume: volume,
            unit: .lb,
            prCount: pr,
            exerciseNames: exercises
        )
    }

    // MARK: Texts

    @Test func dateTextOmitsTheCurrentYear() {
        let now = date(2026, 11, 3)
        #expect(HistoryList.dateText(date(2026, 11, 1), now: now, calendar: Self.toronto) == "Sunday, Nov 1")
        #expect(HistoryList.dateText(date(2025, 12, 31), now: now, calendar: Self.toronto) == "Wednesday, Dec 31, 2025")
    }

    @Test func dateTextUsesTheCalendarTimeZone() {
        // 2026-11-02 02:30 UTC is still Sunday evening in Toronto (after the 2026-11-01 fall-back).
        let instant = Date(timeIntervalSince1970: 1_793_586_600)
        #expect(
            HistoryList.dateText(instant, now: date(2026, 11, 3), calendar: Self.toronto) == "Sunday, Nov 1"
        )
    }

    @Test func durationText() {
        #expect(HistoryList.durationText(seconds: 0) == "<1min")
        #expect(HistoryList.durationText(seconds: 59) == "<1min")
        #expect(HistoryList.durationText(seconds: 60) == "1min")
        #expect(HistoryList.durationText(seconds: 45 * 60 + 30) == "45min")
        #expect(HistoryList.durationText(seconds: 72 * 60) == "1h 12min")
        #expect(HistoryList.durationText(seconds: 3600) == "1h 0min")
        #expect(HistoryList.durationText(seconds: -5) == "<1min")
    }

    @Test func volumeTextRoundsToWholeUnitsWithSeparators() {
        #expect(HistoryList.volumeText(15_421, unit: .lb) == "15,421 lb")
        #expect(HistoryList.volumeText(15_420.5, unit: .kg) == "15,421 kg")
        #expect(HistoryList.volumeText(0, unit: .lb) == "0 lb")
        #expect(HistoryList.volumeText(999.4, unit: .lb) == "999 lb")
    }

    @Test func prTextPluralises() {
        #expect(HistoryList.prText(count: 1) == "1 PR")
        #expect(HistoryList.prText(count: 3) == "3 PRs")
    }

    @Test func accessibilityLabelJoinsTheCard() {
        let now = date(2026, 11, 3)
        let withPRs = entry("Push", at: date(2026, 11, 1), pr: 2, volume: 15_421)
        #expect(
            HistoryList.accessibilityLabel(for: withPRs, now: now, calendar: Self.toronto)
                == "Push, Sunday, Nov 1, 1h 0min, 15,421 lb, 2 PRs"
        )
        let none = entry("Pull", at: date(2026, 11, 1))
        #expect(
            !HistoryList.accessibilityLabel(for: none, now: now, calendar: Self.toronto).contains("PR")
        )
    }

    // MARK: Grouping

    @Test func monthTitle() {
        #expect(HistoryList.monthTitle(date(2026, 11, 15), calendar: Self.toronto) == "November 2026")
    }

    @Test func sectionsGroupByMonthNewestFirst() {
        let entries = [
            entry("a", at: date(2026, 9, 30, 23, 30)),
            entry("b", at: date(2026, 11, 1, 8)),
            entry("c", at: date(2026, 10, 15)),
            entry("d", at: date(2026, 11, 2, 8)),
        ]
        let sections = HistoryList.sections(entries, calendar: Self.toronto)
        #expect(sections.map(\.title) == ["November 2026", "October 2026", "September 2026"])
        #expect(sections[0].entries.map(\.name) == ["d", "b"])
    }

    @Test func monthBoundaryFollowsTheCalendarTimeZone() {
        // 2026-10-01 02:00 UTC is still 30 September in Toronto.
        let instant = Date(timeIntervalSince1970: 1_790_820_000)
        let sections = HistoryList.sections([entry("late", at: instant)], calendar: Self.toronto)
        #expect(sections.map(\.title) == ["September 2026"])
    }

    @Test func noEntriesNoSections() {
        #expect(HistoryList.sections([], calendar: Self.toronto).isEmpty)
    }

    // MARK: Search

    @Test func filterMatchesWorkoutAndExerciseNames() {
        let entries = [
            entry("Push Day", at: date(2026, 11, 1), exercises: ["Bench Press", "Dips"]),
            entry("Legs", at: date(2026, 10, 1), exercises: ["Back Squat"]),
        ]
        #expect(HistoryList.filter(entries, query: "", scope: .all).count == 2)
        #expect(HistoryList.filter(entries, query: "push", scope: .all).map(\.name) == ["Push Day"])
        #expect(HistoryList.filter(entries, query: "  squat ", scope: .all).map(\.name) == ["Legs"])
        #expect(HistoryList.filter(entries, query: "deadlift", scope: .all).isEmpty)
    }

    @Test func prScopeKeepsOnlyWorkoutsWithRecords() {
        let entries = [
            entry("A", at: date(2026, 11, 1), pr: 2, exercises: ["Bench Press"]),
            entry("B", at: date(2026, 10, 1), pr: 0, exercises: ["Bench Press"]),
        ]
        #expect(HistoryList.filter(entries, query: "", scope: .prs).map(\.name) == ["A"])
        #expect(HistoryList.filter(entries, query: "bench", scope: .prs).map(\.name) == ["A"])
        #expect(HistoryList.filter(entries, query: "bench", scope: .all).count == 2)
    }

    // MARK: Building entries

    @MainActor
    @Test func entriesCarryDurationVolumePRsAndNames() throws {
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        let context = container.mainContext
        let bench = UUID()

        func workout(_ name: String, at start: Date, weight: Double, finished: Bool = true) -> Workout {
            let workout = Workout(
                name: name,
                startedAt: start,
                finishedAt: finished ? start.addingTimeInterval(45 * 60) : nil
            )
            let row = WorkoutExercise(
                exerciseID: bench,
                exerciseName: "Bench Press",
                unit: .kg,
                workout: workout
            )
            let work = WorkoutSet(kind: .normal, weight: weight, reps: 5, completed: true, workoutExercise: row)
            let warm = WorkoutSet(
                position: 1,
                kind: .warmup,
                weight: 20,
                reps: 10,
                completed: true,
                workoutExercise: row
            )
            context.insert(workout)
            context.insert(row)
            context.insert(work)
            context.insert(warm)
            return workout
        }

        let first = workout("First", at: date(2026, 10, 1), weight: 100)
        let second = workout("Second", at: date(2026, 10, 8), weight: 100)  // equal: no PR
        let third = workout("Third", at: date(2026, 10, 15), weight: 110)
        let running = workout("Running", at: date(2026, 10, 20), weight: 200, finished: false)
        try context.save()

        let entries = HistoryList.entries(
            from: [first, second, third, running],
            weightType: { $0 == bench ? .barbell : nil },
            options: RecordsOptions(displayUnit: .kg)
        )

        #expect(entries.map(\.name) == ["Third", "Second", "First"])
        #expect(entries.allSatisfy { $0.durationSeconds == 45 * 60 })
        #expect(entries.map(\.volume) == [550, 500, 500])
        #expect(entries.first { $0.name == "Second" }?.prCount == 0)
        #expect((entries.first { $0.name == "First" }?.prCount ?? 0) >= 3)  // e1RM, heaviest, volume
        #expect((entries.first { $0.name == "Third" }?.prCount ?? 0) >= 1)
        #expect(entries.allSatisfy { $0.exerciseNames == ["Bench Press"] })
    }

    @MainActor
    @Test func volumeFollowsTheDisplayUnit() throws {
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        let context = container.mainContext
        let workout = Workout(name: "W", startedAt: date(2026, 10, 1), finishedAt: date(2026, 10, 1, 13))
        let row = WorkoutExercise(exerciseID: UUID(), exerciseName: "Squat", unit: .kg, workout: workout)
        let set = WorkoutSet(weight: 100, reps: 10, completed: true, workoutExercise: row)
        context.insert(workout)
        context.insert(row)
        context.insert(set)
        try context.save()

        let entries = HistoryList.entries(
            from: [workout],
            weightType: { _ in .barbell },
            options: RecordsOptions(displayUnit: .lb)
        )
        // 1000 kg = 2204.6 lb, rounded to 0.5.
        #expect(entries.first?.volume == 2204.5)
        #expect(entries.first?.unit == .lb)
    }

    @Test func durationClampsBackwardsClocks() {
        #expect(HistoryList.duration(from: date(2026, 11, 1), to: nil) == 0)
        #expect(HistoryList.duration(from: date(2026, 11, 1, 13), to: date(2026, 11, 1, 12)) == 0)
        #expect(HistoryList.duration(from: date(2026, 11, 1, 12), to: date(2026, 11, 1, 13)) == 3600)
    }
}
