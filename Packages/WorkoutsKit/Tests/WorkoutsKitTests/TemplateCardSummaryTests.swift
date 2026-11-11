import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct TemplateCardSummaryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_793_000_000)  // 2026-10-26

    private func daysAgo(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }

    private func makeTemplate(_ context: ModelContext, exercises: [(String, Int, Int?)]) -> Template {
        let template = Template(name: "Push")
        context.insert(template)
        for (position, item) in exercises.enumerated() {
            let row = TemplateExercise(
                exerciseName: item.0,
                position: position,
                supersetGroup: item.2,
                template: template
            )
            context.insert(row)
            for index in 0..<item.1 { context.insert(TemplateSet(position: index, templateExercise: row)) }
        }
        return template
    }

    @Test func linesFollowPositionAndOverflow() throws {
        let context = try makeTestContext()
        let template = makeTemplate(
            context,
            exercises: [("A", 3, nil), ("B", 4, 1), ("C", 2, 1), ("D", 1, nil), ("E", 5, nil), ("F", 2, nil)]
        )
        let summary = TemplateCardSummary.make(for: template, finishedWorkouts: [], maxLines: 4, now: now)
        #expect(summary.exerciseCount == 6)
        #expect(summary.lines.map(\.text) == ["A", "B", "C", "D"])
        #expect(summary.lines.map(\.supersetGroup) == [nil, 1, 1, nil])
        #expect(summary.overflowText == "+ 2 more")
        #expect(summary.countText == "6 exercises")
        #expect(summary.lastPerformed == nil)
    }

    @Test func emptyTemplate() throws {
        let context = try makeTestContext()
        let template = makeTemplate(context, exercises: [])
        let summary = TemplateCardSummary.make(for: template, finishedWorkouts: [], now: now)
        #expect(summary.countText == "No exercises")
        #expect(summary.lines.isEmpty && summary.overflowText == nil)
        #expect(summary.accessibilityLabel(name: "Push") == "Push, No exercises")
    }

    @Test func singularCount() throws {
        let context = try makeTestContext()
        let template = makeTemplate(context, exercises: [("A", 1, nil)])
        #expect(TemplateCardSummary.make(for: template, finishedWorkouts: [], now: now).countText == "1 exercise")
    }

    @Test func lastPerformedPrefersLinkedFinishedWorkouts() throws {
        let context = try makeTestContext()
        let template = makeTemplate(context, exercises: [("A", 1, nil)])
        let linkedOld = Workout(name: "Push", startedAt: daysAgo(9), finishedAt: daysAgo(9), template: template)
        let linkedNew = Workout(name: "Push", startedAt: daysAgo(5), finishedAt: daysAgo(5), template: template)
        let inProgress = Workout(name: "Push", startedAt: daysAgo(0), template: template)
        let sameName = Workout(name: "push", startedAt: daysAgo(1), finishedAt: daysAgo(1))
        let summary = TemplateCardSummary.make(
            for: template,
            finishedWorkouts: [linkedOld, linkedNew, inProgress, sameName],
            now: now,
            calendar: calendar
        )
        #expect(summary.lastPerformed == "5 days ago")
        #expect(summary.accessibilityLabel(name: "Push") == "Push, 1 exercise, last done 5 days ago")
    }

    @Test func lastPerformedFallsBackToSameName() throws {
        let context = try makeTestContext()
        let template = makeTemplate(context, exercises: [("A", 1, nil)])
        let imported = Workout(name: "PUSH", startedAt: daysAgo(1), finishedAt: daysAgo(1))
        let other = Workout(name: "Pull", startedAt: daysAgo(0), finishedAt: daysAgo(0))
        let summary = TemplateCardSummary.make(
            for: template,
            finishedWorkouts: [imported, other],
            now: now,
            calendar: calendar
        )
        #expect(summary.lastPerformed == "Yesterday")
        #expect(summary.accessibilityLabel(name: "Push") == "Push, 1 exercise, last done yesterday")
    }

    @Test func lonelySupersetBarIsHidden() throws {
        let context = try makeTestContext()
        // B and C are a pair and both shown; D's partner E falls into "+ 1 more".
        let template = makeTemplate(
            context,
            exercises: [("A", 1, nil), ("B", 1, 1), ("C", 1, 1), ("D", 1, 2), ("E", 1, 2)]
        )
        let summary = TemplateCardSummary.make(for: template, finishedWorkouts: [], maxLines: 4, now: now)
        #expect(summary.lines.map(\.supersetGroup) == [nil, 1, 1, nil])
        #expect(summary.overflow == 1)
        let all = TemplateCardSummary.make(for: template, finishedWorkouts: [], maxLines: 5, now: now)
        #expect(all.lines.map(\.supersetGroup) == [nil, 1, 1, 2, 2])
    }

    @Test func indexLinkedBeatsSameNameEvenWhenOlder() throws {
        let context = try makeTestContext()
        let template = makeTemplate(context, exercises: [("A", 1, nil)])
        let linked = Workout(name: "Renamed", startedAt: daysAgo(9), finishedAt: daysAgo(9), template: template)
        let sameName = Workout(name: "push", startedAt: daysAgo(1), finishedAt: daysAgo(1))
        let index = TemplateCardSummary.LastPerformedIndex(finishedWorkouts: [sameName, linked])
        #expect(index.lastPerformed(of: template) == daysAgo(9))
    }

    @Test func indexNewestWinsAndIgnoresInProgress() throws {
        let context = try makeTestContext()
        let template = makeTemplate(context, exercises: [("A", 1, nil)])
        let old = Workout(name: "Push", startedAt: daysAgo(9), finishedAt: daysAgo(9), template: template)
        let new = Workout(name: "Push", startedAt: daysAgo(5), finishedAt: daysAgo(5), template: template)
        let running = Workout(name: "Push", startedAt: daysAgo(0), template: template)
        let index = TemplateCardSummary.LastPerformedIndex(finishedWorkouts: [old, running, new])
        #expect(index.lastPerformed(of: template) == daysAgo(5))
        // Same-name fallback for an unlinked template: case-insensitive, the newest finished one.
        let other = Template(name: "PUSH")
        context.insert(other)
        #expect(index.lastPerformed(of: other) == daysAgo(5))
    }

    @Test func indexOfNothingAnswersNil() throws {
        let context = try makeTestContext()
        let template = makeTemplate(context, exercises: [("A", 1, nil)])
        #expect(TemplateCardSummary.LastPerformedIndex(finishedWorkouts: []).lastPerformed(of: template) == nil)
        #expect(TemplateCardSummary.LastPerformedIndex().lastPerformed(of: template) == nil)
    }

    @Test func indexMatchesPerTemplateAnswer() throws {
        let context = try makeTestContext()
        let push = makeTemplate(context, exercises: [("A", 1, nil)])
        let pull = Template(name: "Pull")
        context.insert(pull)
        let workouts = [
            Workout(name: "Push", startedAt: daysAgo(3), finishedAt: daysAgo(3), template: push),
            Workout(name: "pull", startedAt: daysAgo(2), finishedAt: daysAgo(2)),
            Workout(name: "Pull", startedAt: daysAgo(6), finishedAt: daysAgo(6)),
        ]
        let index = TemplateCardSummary.LastPerformedIndex(finishedWorkouts: workouts)
        for template in [push, pull] {
            let viaIndex = TemplateCardSummary.make(for: template, index: index, now: now, calendar: calendar)
            let direct = TemplateCardSummary.make(
                for: template,
                finishedWorkouts: workouts,
                now: now,
                calendar: calendar
            )
            #expect(viaIndex == direct)
        }
        #expect(index.lastPerformed(of: pull) == daysAgo(2))
    }

    // MARK: Sets per line

    private func detail(_ sets: [TemplateSet]) throws -> String? {
        let context = try makeTestContext()
        let template = Template(name: "Push")
        context.insert(template)
        let row = TemplateExercise(exerciseName: "A", template: template)
        context.insert(row)
        for (position, set) in sets.enumerated() {
            set.position = position
            set.templateExercise = row
            context.insert(set)
        }
        return TemplateCardSummary.make(for: template, finishedWorkouts: [], now: now).lines.first?.detail
    }

    @Test func equalRepsReadCountTimesReps() throws {
        #expect(try detail((0..<4).map { _ in TemplateSet(reps: 8) }) == "4 × 8")
    }

    @Test func mixedRepsReadSets() throws {
        #expect(try detail([TemplateSet(reps: 8), TemplateSet(reps: 6), TemplateSet(reps: 8)]) == "3 sets")
    }

    @Test func unplannedRepsReadSets() throws {
        #expect(try detail([TemplateSet(), TemplateSet()]) == "2 sets")
        #expect(try detail([TemplateSet(reps: 8), TemplateSet()]) == "2 sets")
    }

    @Test func warmupsAreExcluded() throws {
        let sets = [TemplateSet(kind: .warmup, reps: 12), TemplateSet(reps: 5), TemplateSet(reps: 5)]
        #expect(try detail(sets) == "2 × 5")
        #expect(try detail([TemplateSet(kind: .warmup, reps: 12)]) == nil)
    }

    @Test func timedSets() throws {
        #expect(try detail((0..<3).map { _ in TemplateSet(durationSeconds: 45) }) == "3 × 45 s")
        #expect(try detail((0..<2).map { _ in TemplateSet(durationSeconds: 90) }) == "2 × 1:30")
        #expect(try detail([TemplateSet(durationSeconds: 45), TemplateSet(durationSeconds: 60)]) == "2 sets")
    }

    @Test func noWorkingSetsAnswerNil() throws {
        #expect(try detail([]) == nil)
    }

    @Test func oneSetIsSingular() throws {
        #expect(try detail([TemplateSet()]) == "1 set")
        #expect(try detail([TemplateSet(reps: 10)]) == "1 × 10")
    }

    @Test func sixLinesWithOverflow() throws {
        let context = try makeTestContext()
        let names = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let template = makeTemplate(context, exercises: names.map { ($0, 3, nil) })
        let summary = TemplateCardSummary.make(for: template, finishedWorkouts: [], maxLines: 6, now: now)
        #expect(summary.lines.map(\.text) == ["A", "B", "C", "D", "E", "F"])
        #expect(summary.lines.allSatisfy { $0.detail == "3 sets" })
        #expect(summary.overflowText == "+ 2 more")
        #expect(summary.exerciseCount == 8)
    }

    // MARK: Last duration

    @Test func lastDurationComesFromTheNewestFinishedWorkout() throws {
        let context = try makeTestContext()
        let template = makeTemplate(context, exercises: [("A", 1, nil)])
        let old = Workout(
            name: "Push",
            startedAt: daysAgo(9),
            finishedAt: daysAgo(9).addingTimeInterval(1_800),
            template: template
        )
        let new = Workout(
            name: "Push",
            startedAt: daysAgo(4),
            finishedAt: daysAgo(4).addingTimeInterval(3_120),
            template: template
        )
        let running = Workout(name: "Push", startedAt: daysAgo(0), template: template)
        let summary = TemplateCardSummary.make(
            for: template,
            finishedWorkouts: [old, running, new],
            now: now,
            calendar: calendar
        )
        #expect(summary.lastPerformed == "4 days ago")
        #expect(summary.lastDurationText == "52min")
        #expect(
            summary.accessibilityLabel(name: "Push")
                == "Push, 1 exercise, last done 4 days ago, last session 52 minutes"
        )
    }

    @Test func lastDurationAbsentWhenNeverPerformed() throws {
        let context = try makeTestContext()
        let template = makeTemplate(context, exercises: [("A", 1, nil)])
        let running = Workout(name: "Push", startedAt: daysAgo(0), template: template)
        let summary = TemplateCardSummary.make(for: template, finishedWorkouts: [running], now: now)
        #expect(summary.lastDurationText == nil)
        #expect(summary.accessibilityLabel(name: "Push") == "Push, 1 exercise")
    }

    @Test func lastDurationFollowsTheSameNameFallback() throws {
        let context = try makeTestContext()
        let template = makeTemplate(context, exercises: [("A", 1, nil)])
        let imported = Workout(
            name: "push",
            startedAt: daysAgo(2),
            finishedAt: daysAgo(2).addingTimeInterval(4_500)
        )
        let index = TemplateCardSummary.LastPerformedIndex(finishedWorkouts: [imported])
        #expect(index.lastDurationSeconds(of: template) == 4_500)
        #expect(
            TemplateCardSummary.make(for: template, index: index, now: now, calendar: calendar).lastDurationText
                == "1h 15min"
        )
    }

    /// A fresh context over a saved folder holding one template with two exercises (3 and 2 sets): every object is a
    /// fault, as the Workout tab's grid has them.
    private func faultedFolder() throws -> (ModelContext, TemplateFolder, Template) {
        let container = try makeTestContainer()
        let seed = ModelContext(container)
        let folder = TemplateFolder(name: "Legs")
        seed.insert(folder)
        makeTemplate(seed, exercises: [("A", 3, nil), ("B", 2, nil)]).folder = folder
        try seed.save()
        let context = ModelContext(container)
        let template = try #require(try context.fetch(FetchDescriptor<Template>()).first)
        _ = (template.exercises ?? []).flatMap { $0.sets ?? [] }
        return (context, try #require(try context.fetch(FetchDescriptor<TemplateFolder>()).first), template)
    }

    @Test func summaryOfATemplateDeletedWithItsFolderIsHarmless() throws {
        let (context, folder, template) = try faultedFolder()
        let exercise = try #require(template.exercises?.first)
        let set = try #require(exercise.sets?.first)
        try FolderOperations.delete(folder, .deleteTemplates, in: context)
        #expect(template.isGone && exercise.isGone && set.isGone)
        let summary = TemplateCardSummary.make(for: template, finishedWorkouts: [], now: now)
        #expect(summary.lines.allSatisfy { $0.detail == nil })
    }

    @Test func summaryOfAStandaloneDeletedTemplateIsHarmless() throws {
        let (context, _, template) = try faultedFolder()
        try FolderOperations.delete(template, in: context)
        let summary = TemplateCardSummary.make(for: template, finishedWorkouts: [], now: now)
        #expect(summary.lines.allSatisfy { $0.detail == nil })
    }

    @Test func detachedFixturesKeepTheirSetsText() {
        let template = Template(name: "Push")
        #expect(!template.isGone)
        let row = TemplateExercise(exerciseName: "Bench", position: 0, template: template)
        template.exercises = [row]
        row.sets = (0..<3).map { TemplateSet(position: $0, templateExercise: row) }
        let summary = TemplateCardSummary.make(for: template, finishedWorkouts: [], now: now)
        #expect(summary.lines.map(\.text) == ["Bench"])
        #expect(summary.lines.first?.detail == "3 sets")
    }

    @Test func accessibilityEntriesSpeakNamesSetsAndOverflow() throws {
        let context = try makeTestContext()
        let template = Template(name: "Push")
        context.insert(template)
        let plans: [(String, [TemplateSet])] = [
            ("Bench", (0..<4).map { _ in TemplateSet(reps: 6) }),
            ("Plank", (0..<3).map { _ in TemplateSet(durationSeconds: 45) }),
            ("Curl", [TemplateSet(reps: 10)]),
            ("Dip", [TemplateSet(reps: 8), TemplateSet()]),
            ("Stretch", []),
        ]
        for (position, plan) in plans.enumerated() {
            let row = TemplateExercise(exerciseName: plan.0, position: position, template: template)
            context.insert(row)
            for (index, set) in plan.1.enumerated() {
                set.position = index
                set.templateExercise = row
                context.insert(set)
            }
        }
        let summary = TemplateCardSummary.make(for: template, finishedWorkouts: [], maxLines: 4, now: now)
        #expect(
            summary.accessibilityEntries.map { [$0.label, $0.value] } == [
                ["Bench", "4 sets of 6 reps"],
                ["Plank", "3 sets of 45 seconds"],
                ["Curl", "1 set of 10 reps"],
                ["Dip", "2 sets"],
                ["And 1 more", "exercises"],
            ]
        )
    }

    @Test func accessibilityEntriesWithoutSetsOrOverflow() throws {
        let context = try makeTestContext()
        let template = makeTemplate(context, exercises: [("A", 0, nil)])
        let summary = TemplateCardSummary.make(for: template, finishedWorkouts: [], now: now)
        #expect(summary.accessibilityEntries.map { [$0.label, $0.value] } == [["A", "No sets"]])
        let empty = TemplateCardSummary.make(for: Template(name: "E"), finishedWorkouts: [], now: now)
        #expect(empty.accessibilityEntries.isEmpty)
    }

    @Test func relativeTextBuckets() {
        func text(_ days: Int) -> String {
            TemplateCardSummary.relativeText(daysAgo(days), now: now, calendar: calendar)
        }
        #expect(text(0) == "Today")
        #expect(text(-3) == "Today")
        #expect(text(1) == "Yesterday")
        #expect(text(2) == "2 days ago")
        #expect(text(13) == "13 days ago")
        #expect(text(14) == "2 weeks ago")
        #expect(text(59) == "8 weeks ago")
        #expect(text(60) == "Aug 27, 2026")
    }
}
