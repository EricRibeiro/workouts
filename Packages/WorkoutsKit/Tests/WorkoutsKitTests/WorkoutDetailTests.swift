import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite @MainActor struct WorkoutDetailTests {
    private static let toronto = TestSupport.torontoCalendar

    private func date(_ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 5) -> Date {
        let parts = DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)
        return Self.toronto.date(from: parts) ?? .distantPast
    }

    private let bench = UUID()
    private let curl = UUID()
    private let options = RecordsOptions(displayUnit: .kg)

    /// A finished workout with one row per `(exerciseID, name, group, sets)`; sets are `(kind, weight, reps, completed)`.
    private func workout(
        _ context: ModelContext,
        name: String = "Push",
        at start: Date,
        unit: WeightUnit = .kg,
        finished: Bool = true,
        rows: [(UUID, String, Int?, [(SetKind, Double, Int, Bool)])]
    ) -> Workout {
        let workout = Workout(
            name: name,
            note: "felt good",
            startedAt: start,
            finishedAt: finished ? start.addingTimeInterval(50 * 60) : nil
        )
        context.insert(workout)
        for (position, spec) in rows.enumerated() {
            let row = WorkoutExercise(
                exerciseID: spec.0,
                exerciseName: spec.1,
                position: position,
                supersetGroup: spec.2,
                unit: unit,
                workout: workout
            )
            context.insert(row)
            for (index, set) in spec.3.enumerated() {
                context.insert(
                    WorkoutSet(
                        position: index,
                        kind: set.0,
                        weight: set.1,
                        reps: set.2,
                        completed: set.3,
                        workoutExercise: row
                    )
                )
            }
        }
        return workout
    }

    private func detail(_ id: UUID, _ all: [Workout], options: RecordsOptions? = nil) -> WorkoutDetail? {
        WorkoutDetail.make(
            id: id,
            from: all,
            weightType: { _ in .barbell },
            options: options ?? self.options,
            now: date(11, 4),
            calendar: Self.toronto
        )
    }

    // MARK: Header

    @Test func headerTextsAndSentence() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let first = workout(
            context,
            at: date(11, 1),
            rows: [(bench, "Bench Press", nil, [(.normal, 100, 5, true), (.normal, 100, 5, true)])]
        )
        let detail = try #require(detail(first.id, [first]))
        #expect(detail.dateText == "Sunday, Nov 1 · 10:05 AM")
        #expect(detail.durationText == "50min")
        #expect(detail.volumeText == "1,000 kg")
        #expect(detail.note == "felt good")
        #expect(detail.prCount == 3)  // first session: e1RM, heaviest, set volume
        #expect(
            detail.headerAccessibilityLabel
                == "Push, Sunday, Nov 1 · 10:05 AM, 50min, 1,000 kg, 3 PRs, Note: felt good"
        )
    }

    @Test func headerSentenceAppendsOnlyTheHealthValuesThatExist() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let first = workout(
            holder.mainContext,
            at: date(11, 1),
            rows: [(bench, "Bench Press", nil, [(.normal, 100, 5, true), (.normal, 100, 5, true)])]
        )
        let detail = try #require(detail(first.id, [first]))
        let base = detail.headerAccessibilityLabel
        let locale = Locale(identifier: "en_US")
        #expect(detail.accessibilityLabel(health: nil, locale: locale) == base)

        let empty = HealthWorkoutSummary(healthWorkoutID: "h", start: first.startedAt, end: first.startedAt)
        #expect(detail.accessibilityLabel(health: empty, locale: locale) == base)

        let full = HealthWorkoutSummary(
            healthWorkoutID: "h",
            start: first.startedAt,
            end: first.startedAt,
            activeEnergyKcal: 266.4,
            totalEnergyKcal: 410,
            avgHeartRate: 128,
            maxHeartRate: 162,
            effort: HealthEffort(score: 6, isEstimated: true),
            weatherTemperatureCelsius: 16,
            weatherHumidityPercent: 83
        )
        #expect(
            detail.accessibilityLabel(health: full, locale: locale)
                == base + ", 266 active calories, 410 total calories, average heart rate 128, maximum heart rate 162"
                + ", effort 6 Moderate, estimated, weather 61°F, 83% humidity"
        )

        let partial = HealthWorkoutSummary(
            healthWorkoutID: "h",
            start: first.startedAt,
            end: first.startedAt,
            avgHeartRate: 120,
            effort: HealthEffort(score: 8, isEstimated: false)
        )
        #expect(
            detail.accessibilityLabel(health: partial, locale: locale)
                == base + ", average heart rate 120, effort 8 Hard"
        )
    }

    @Test func dateTextAddsTheYearOnlyWhenItIsNotThisOne() {
        #expect(
            WorkoutDetail.dateText(date(11, 1), calendar: Self.toronto, now: date(11, 4))
                == "Sunday, Nov 1 · 10:05 AM"
        )
        let old = Self.toronto.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 21, minute: 30))
        #expect(
            WorkoutDetail.dateText(old ?? .distantPast, calendar: Self.toronto, now: date(11, 4))
                == "Wednesday, Dec 31, 2025 · 9:30 PM"
        )
    }

    @Test func unknownAndUnfinishedWorkoutsGiveNoDetail() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let running = workout(context, at: date(11, 1), finished: false, rows: [(bench, "Bench", nil, [])])
        #expect(detail(running.id, [running]) == nil)
        #expect(detail(UUID(), []) == nil)
    }

    // MARK: Exercises and sets

    @Test func onlyCompletedSetsAreListedWithKindLettersAndExercisesWithoutOneAreLeftOut() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let w = workout(
            context,
            at: date(11, 1),
            rows: [
                (
                    bench, "Bench Press",
                    nil,
                    [
                        (.warmup, 60, 8, true), (.normal, 100, 5, true), (.normal, 100, 5, false),
                        (.drop, 80, 8, true), (.failure, 70, 6, true),
                    ]
                ),
                (curl, "Curl", nil, [(.normal, 20, 10, false)]),
            ]
        )
        let detail = try #require(detail(w.id, [w]))
        #expect(detail.exercises.map(\.name) == ["Bench Press"])
        let block = detail.exercises[0]
        #expect(block.sets.map(\.label) == ["W", "2", "D", "F"])
        #expect(block.sets.map(\.text) == ["60 kg × 8", "100 kg × 5", "80 kg × 8", "70 kg × 6"])
        #expect(block.sets[0].accessibilityLabel == "Set 1, warm-up, 60 kg × 8")
        #expect(block.bestSetText == "100 kg × 5")
    }

    @Test func supersetRowsShareANumber() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let w = workout(
            context,
            at: date(11, 1),
            rows: [
                (bench, "Bench Press", 4, [(.normal, 100, 5, true)]),
                (curl, "Curl", 4, [(.normal, 20, 10, true)]),
                (UUID(), "Row", nil, [(.normal, 50, 10, true)]),
            ]
        )
        let detail = try #require(detail(w.id, [w]))
        #expect(detail.exercises.map(\.supersetNumber) == [1, 1, nil])
        #expect(detail.exercises[0].accessibilityLabel.contains("superset 1"))
    }

    @Test func weightsFollowTheDisplayUnit() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let w = workout(
            context,
            at: date(11, 1),
            unit: .lb,
            rows: [(bench, "Bench Press", nil, [(.normal, 100, 5, true)])]
        )
        let kg = try #require(detail(w.id, [w], options: RecordsOptions(displayUnit: .kg)))
        #expect(kg.exercises[0].sets[0].text == "45.5 kg × 5")  // 45.36 kg rounded to 0.5
        let lb = try #require(detail(w.id, [w], options: RecordsOptions(displayUnit: .lb)))
        #expect(lb.exercises[0].sets[0].text == "100 lb × 5")
        #expect(lb.volumeText == "500 lb")
    }

    // MARK: Records

    @Test func recordsAreJudgedAgainstEarlierWorkoutsOnly() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let early = workout(
            context,
            name: "A",
            at: date(10, 1),
            rows: [(bench, "Bench Press", nil, [(.normal, 100, 5, true)])]
        )
        let equal = workout(
            context,
            name: "B",
            at: date(10, 8),
            rows: [(bench, "Bench Press", nil, [(.normal, 100, 5, true)])]
        )
        let heavier = workout(
            context,
            name: "C",
            at: date(10, 15),
            rows: [(bench, "Bench Press", nil, [(.normal, 100, 5, true), (.normal, 110, 5, true)])]
        )
        let all = [early, equal, heavier]

        let second = try #require(detail(equal.id, all))
        #expect(second.prCount == 0)
        #expect(second.exercises[0].prLines.isEmpty)
        #expect(second.exercises[0].sets.allSatisfy { !$0.isPR })

        let third = try #require(detail(heavier.id, all))
        #expect(third.prCount == third.exercises[0].prLines.count)
        #expect(third.prCount >= 2)
        // The trophy sits on the 110 kg set, not on the 100 kg one.
        #expect(third.exercises[0].sets.map(\.isPR) == [false, true])
        #expect(third.exercises[0].prLines.contains { $0.hasPrefix("Heaviest: 110 kg") })
        #expect(third.exercises[0].accessibilityLabel.contains("personal record"))

        // The first workout is unaffected by the later ones, and agrees with the History row.
        let first = try #require(detail(early.id, all))
        let entries = HistoryList.entries(from: all, weightType: { _ in .barbell }, options: options)
        for entry in entries {
            #expect(detail(entry.id, all)?.prCount == entry.prCount)
        }
        #expect(first.prCount == 3)
    }

    @Test func otherExercisesInTheHistoryDoNotChangeTheDetail() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let early = workout(
            context,
            name: "A",
            at: date(10, 1),
            rows: [(bench, "Bench Press", nil, [(.normal, 100, 5, true)])]
        )
        let target = workout(
            context,
            name: "B",
            at: date(10, 8),
            rows: [(bench, "Bench Press", nil, [(.normal, 110, 5, true)])]
        )
        let unrelated = workout(
            context,
            name: "C",
            at: date(10, 3),
            rows: [(curl, "Curl", nil, [(.normal, 500, 5, true)])]
        )
        let alone = try #require(detail(target.id, [early, target]))
        let crowded = try #require(detail(target.id, [early, unrelated, target]))
        #expect(alone == crowded)
        #expect(alone.prCount > 0)
    }

    @Test func prLinesGroupThousands() {
        func line(_ kind: RecordKind, value: Double, weight: Double = 0, reps: Int = 0) -> String {
            WorkoutDetail.prLine(
                PersonalRecord(kind: kind, value: value, weight: weight, reps: reps),
                unit: .lb,
                weightType: .barbell
            )
        }
        #expect(line(.e1rm, value: 1929) == "Est. 1RM: 1,929 lb")
        #expect(line(.e1rm, value: 1929.5) == "Est. 1RM: 1,929.5 lb")
        #expect(line(.heaviest, value: 1250, weight: 1250, reps: 1) == "Heaviest: 1,250 lb")
        #expect(line(.bestVolumeSet, value: 12_345) == "Set volume: 12,345 lb")
        #expect(line(.repsAtWeight, value: 3, weight: 1500, reps: 3) == "Reps: 3 at 1,500 lb")
        #expect(line(.e1rm, value: 117.5) == "Est. 1RM: 117.5 lb")
    }

    @Test func prLineTexts() {
        func line(_ kind: RecordKind, value: Double, weight: Double = 0, reps: Int = 0, type: WeightType = .barbell)
            -> String
        {
            WorkoutDetail.prLine(
                PersonalRecord(kind: kind, value: value, weight: weight, reps: reps),
                unit: .lb,
                weightType: type
            )
        }
        #expect(line(.e1rm, value: 116.5, weight: 100, reps: 5) == "Est. 1RM: 116.5 lb")
        #expect(line(.heaviest, value: 100, weight: 100, reps: 5) == "Heaviest: 100 lb")
        #expect(line(.heaviest, value: 20, weight: 20, reps: 8, type: .assisted) == "Least assistance: 20 lb")
        #expect(line(.bestVolumeSet, value: 500, weight: 100, reps: 5) == "Set volume: 500 lb")
        #expect(line(.repsAtWeight, value: 8, weight: 100, reps: 8) == "Reps: 8 at 100 lb")
        #expect(line(.repsAtWeight, value: 12, weight: 0, reps: 12, type: .bodyweight) == "Reps: 12")
        #expect(line(.longestDuration, value: 90) == "Duration: 1:30")
        #expect(line(.longestDuration, value: 45) == "Duration: 45 s")
    }

    // MARK: Save as Template

    private func templates(_ context: ModelContext) throws -> [Template] {
        try context.fetch(FetchDescriptor<Template>())
    }

    @Test func saveAsTemplateCopiesCompletedSetsAsPlannedValues() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let w = workout(
            context,
            at: date(11, 1),
            rows: [
                (
                    bench, "Bench Press", 2,
                    [(.warmup, 60, 8, true), (.normal, 100, 5, true), (.normal, 100, 5, false)]
                ),
                (curl, "Curl", 2, [(.normal, 20, 10, true)]),
                (UUID(), "Skipped", nil, [(.normal, 5, 5, false)]),
            ]
        )
        try context.save()
        let folder = TemplateFolder(name: "Push Days", position: 3)
        context.insert(folder)
        let made = try WorkoutDetail.saveAsTemplate(w, to: .folder(folder), in: context, now: date(11, 2))

        let saved = try templates(context)
        #expect(saved.count == 1)
        #expect(made.name == "Push")
        #expect(made.note == "felt good")
        #expect(made.folder?.id == folder.id)
        #expect(made.id != w.id)

        let rows = (made.exercises ?? []).sorted { $0.position < $1.position }
        #expect(rows.map(\.exerciseName) == ["Bench Press", "Curl"])
        #expect(rows.map(\.position) == [0, 1])
        #expect(rows.map(\.supersetGroup) == [2, 2])
        #expect(Set(rows.map(\.id)).isDisjoint(with: Set((w.exercises ?? []).map(\.id))))
        let sets = (rows[0].sets ?? []).sorted { $0.position < $1.position }
        #expect(sets.map(\.kind) == [.warmup, .normal])
        #expect(sets.map(\.weight) == [60, 100])
        #expect(sets.map(\.reps) == [8, 5])
        #expect(sets.map(\.position) == [0, 1])
        // The workout is untouched.
        #expect((w.exercises ?? []).count == 3)
    }

    @Test func saveAsTemplateWithNoFolderOrANewFolder() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let w = workout(
            context,
            at: date(11, 1),
            rows: [(bench, "Bench Press", nil, [(.normal, 100, 5, true)])]
        )
        let loose = try WorkoutDetail.saveAsTemplate(w, named: "  My Push ", to: .none, in: context)
        #expect(loose.folder == nil)
        #expect(loose.name == "My Push")

        let filed = try WorkoutDetail.saveAsTemplate(w, to: .newFolder(named: "Templates"), in: context)
        #expect(filed.folder?.name == "Templates")
        let again = try WorkoutDetail.saveAsTemplate(w, named: "", to: .folder(try #require(filed.folder)), in: context)
        #expect(again.name == "Push")  // blank falls back to the workout's own name
        #expect(again.position == filed.position + 1)
        #expect(try context.fetch(FetchDescriptor<TemplateFolder>()).count == 1)
    }
}
