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

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer.workouts(inMemory: true, cloudKit: false))
    }

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
        let context = try makeContext()
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
        let context = try makeContext()
        let template = makeTemplate(context, exercises: [])
        let summary = TemplateCardSummary.make(for: template, finishedWorkouts: [], now: now)
        #expect(summary.countText == "No exercises")
        #expect(summary.lines.isEmpty && summary.overflowText == nil)
        #expect(summary.accessibilityLabel(name: "Push") == "Push, No exercises")
    }

    @Test func singularCount() throws {
        let context = try makeContext()
        let template = makeTemplate(context, exercises: [("A", 1, nil)])
        #expect(TemplateCardSummary.make(for: template, finishedWorkouts: [], now: now).countText == "1 exercise")
    }

    @Test func lastPerformedPrefersLinkedFinishedWorkouts() throws {
        let context = try makeContext()
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
        let context = try makeContext()
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
