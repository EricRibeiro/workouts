import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

/// The pre-optimisation computation: `prsInSession` once per session, each refolding the earlier history.
@MainActor
fileprivate func perSessionPRCounts(
    _ workouts: [Workout],
    weightType: (UUID) -> WeightType?,
    options: RecordsOptions
) -> [UUID: Int] {
    let finished = workouts.filter { $0.finishedAt != nil }
    var counts: [UUID: Int] = [:]
    for (_, sessions) in ExerciseBestSets.sessions(from: finished, weightType: weightType) {
        for session in sessions {
            counts[session.workoutID, default: 0] +=
                prsInSession(
                    history: sessions,
                    session: session,
                    weightType: session.weightType,
                    options: options
                ).count
        }
    }
    return counts
}

@Suite struct HistoryListTests {
    private static let toronto = TestSupport.torontoCalendar

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
        let container = try makeTestContainer()
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
        let container = try makeTestContainer()
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

    // MARK: PR counts: one pass equals one fold per session

    private static func realCatalog() throws -> LibraryCatalog {
        try LibraryCatalog(data: Data(contentsOf: repoRoot.appendingPathComponent("Resources/Library/library.json")))
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @MainActor
    @Test func prCountsMatchThePerSessionFoldOnSampleData() throws {
        let catalog = try Self.realCatalog()
        let container = try makeTestContainer()
        let context = container.mainContext
        try SampleData.seed(into: context, catalog: catalog, now: Date(timeIntervalSince1970: 1_793_000_000), seed: 1)
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        #expect(!workouts.isEmpty)

        for unit in [WeightUnit.kg, .lb] {
            let options = RecordsOptions(displayUnit: unit)
            let weightType: (UUID) -> WeightType? = { catalog.exercise(id: $0)?.weightType }
            let expected = perSessionPRCounts(workouts, weightType: weightType, options: options)
            let entries = HistoryList.entries(from: workouts, weightType: weightType, options: options)

            #expect(entries.count == workouts.filter { $0.finishedAt != nil }.count)
            #expect(entries.contains { $0.prCount > 0 })
            for entry in entries {
                #expect(entry.prCount == expected[entry.id, default: 0], "\(entry.name) in \(unit)")
            }
        }
    }

    @Test func prsForEachSessionMatchesPrsInSessionIncludingTies() {
        let exercise = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func session(_ day: Int, _ weights: [Double]) -> Session {
            Session(
                workoutID: UUID(),
                time: t0.addingTimeInterval(Double(day) * 86_400),
                exerciseID: exercise,
                weightType: .barbell,
                sets: weights.map { LoggedSet(kind: .normal, weight: $0, unit: .kg, reps: 5, completed: true) }
            )
        }
        // Day 3 appears twice (two rows of one exercise in a workout, or two workouts at the same instant): neither
        // may count toward the other. Input is deliberately out of order.
        let sessions = [
            session(3, [110]), session(0, [100]), session(3, [120, 100]), session(1, [100]), session(5, [90]),
            session(4, [125]),
        ]
        let options = RecordsOptions(displayUnit: .kg)
        let results = prsForEachSession(sessions, weightType: .barbell, options: options)

        #expect(results.map(\.session.time) == results.map(\.session.time).sorted())
        #expect(results.count == sessions.count)
        for (session, prs) in results {
            #expect(
                prs == prsInSession(history: sessions, session: session, weightType: .barbell, options: options)
            )
        }
        #expect(results.contains { !$0.prs.isEmpty })
    }

    @Test func prsForEachSessionOfNothingIsNothing() {
        #expect(prsForEachSession([], weightType: .barbell, options: RecordsOptions()).isEmpty)
    }
}

/// Eric's real 553-workout web export, imported into memory (`scripts/export-web`). Personal data and gitignored, so
/// the suite runs only where it exists; a worktree finds the main checkout's copy by walking up the directory tree.
private nonisolated enum HistoryWebExportFixture {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static let url: URL? = {
        var directory = repoRoot
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent("docs/port/fixtures/web-export.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        return nil
    }()
}

@Suite(
    .enabled(
        if: HistoryWebExportFixture.url != nil,
        "docs/port/fixtures/web-export.json is missing: run scripts/export-web"
    )
)
struct HistoryListWebExportTests {
    @MainActor
    @Test func entriesOnTheRealHistoryMatchThePerSessionFold() throws {
        let fixture = try #require(HistoryWebExportFixture.url)
        let doc = try WorkoutsJSON.decode(Data(contentsOf: fixture))
        let catalog = try LibraryCatalog(
            data: Data(
                contentsOf: HistoryWebExportFixture.repoRoot.appendingPathComponent("Resources/Library/library.json")
            )
        )
        let container = try makeTestContainer()
        let context = container.mainContext
        _ = try Importer.apply(doc, to: context, catalog: catalog)

        let custom = Dictionary(
            try context.fetch(FetchDescriptor<Exercise>()).map { ($0.id, $0.weightType) },
            uniquingKeysWith: { first, _ in first }
        )
        let weightType: (UUID) -> WeightType? = { catalog.exercise(id: $0)?.weightType ?? custom[$0] }
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let finished = workouts.filter { $0.finishedAt != nil }
        let options = RecordsOptions(displayUnit: .lb)

        let clock = ContinuousClock()
        var entries: [HistoryEntry] = []
        let elapsed = clock.measure {
            entries = HistoryList.entries(from: workouts, weightType: weightType, options: options)
        }
        print("HistoryList.entries: \(finished.count) workouts in \(elapsed)")

        #expect(entries.count == finished.count)
        #expect(finished.count > 100)
        #expect(entries.contains { $0.prCount > 0 })

        let oldElapsed = clock.measure {
            let expected = perSessionPRCounts(finished, weightType: weightType, options: options)
            for entry in entries {
                #expect(entry.prCount == expected[entry.id, default: 0], "\(entry.name) \(entry.startedAt)")
            }
        }
        print("per-session prsInSession (old way) plus comparison: \(oldElapsed)")
    }
}
