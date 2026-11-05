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
        #expect(summary.lines.map(\.text) == ["3 × A", "4 × B", "2 × C", "1 × D"])
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
