import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

/// Second bug-review round: PR counts agree between History and Finish, singular "1 rep", Gregorian month/year text.
@Suite @MainActor struct ReviewRound2Tests {
    private let bench = UUID()
    private let options = RecordsOptions(displayUnit: .kg)

    private func date(_ day: Int) -> Date {
        let parts = DateComponents(year: 2026, month: 11, day: day, hour: 10)
        return TestSupport.torontoCalendar.date(from: parts) ?? .distantPast
    }

    private func finishedWorkout(
        _ context: ModelContext,
        day: Int,
        rows: [[(Double, Int)]]
    ) -> Workout {
        let start = date(day)
        let workout = Workout(name: "Push", startedAt: start, finishedAt: start.addingTimeInterval(3_000))
        context.insert(workout)
        for (position, sets) in rows.enumerated() {
            let row = WorkoutExercise(
                exerciseID: bench,
                exerciseName: "Bench",
                position: position,
                unit: .kg,
                workout: workout
            )
            context.insert(row)
            for (index, set) in sets.enumerated() {
                context.insert(
                    WorkoutSet(position: index, weight: set.0, reps: set.1, completed: true, workoutExercise: row)
                )
            }
        }
        return workout
    }

    // MARK: 1. One exercise twice in a workout

    @Test func historyAndFinishCountTheSameExerciseTwiceAsOneSession() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let old = finishedWorkout(context, day: 1, rows: [[(100, 5)]])
        let today = finishedWorkout(context, day: 2, rows: [[(110, 5)], [(105, 5)]])
        let all = [old, today]

        // Finish: one merged session per exercise against the earlier history.
        let oldSession = Session(
            workoutID: old.id,
            time: old.startedAt,
            exerciseID: bench,
            weightType: .barbell,
            sets: [LoggedSet(weight: 100, unit: .kg, reps: 5)]
        )
        let merged = Session(
            workoutID: today.id,
            time: today.startedAt,
            exerciseID: bench,
            weightType: .barbell,
            sets: [LoggedSet(weight: 110, unit: .kg, reps: 5), LoggedSet(weight: 105, unit: .kg, reps: 5)]
        )
        let finish = prsInSession(history: [oldSession], session: merged, weightType: .barbell, options: options)
        #expect(finish.count == 4)

        // History cards.
        let summary = HistoryDashboard.build(from: all, weightType: { _ in .barbell }, options: options)
        let entry = try #require(summary.entries.first { $0.id == today.id })
        #expect(entry.prCount == finish.count)

        // Workout detail header and the per-row sets.
        let detail = try #require(
            WorkoutDetail.make(
                id: today.id,
                from: all,
                weightType: { _ in .barbell },
                options: options,
                now: date(3),
                calendar: TestSupport.torontoCalendar
            )
        )
        #expect(detail.prCount == finish.count)
        #expect(detail.exercises.map(\.sets.count) == [1, 1])
        #expect(detail.exercises[0].sets[0].text.contains("110"))
        #expect(detail.exercises[1].sets[0].text.contains("105"))

        // Exercise detail History tab: the two rows' counts add up too.
        let sessions = ExerciseBestSets.sessions(from: all, weightType: { _ in .barbell })[bench] ?? []
        let history = ExerciseHistory.sessions(
            sessions,
            names: [old.id: "Push", today.id: "Push"],
            weightType: .barbell,
            options: options
        )
        #expect(history.filter { $0.workoutID == today.id }.reduce(0) { $0 + $1.prCount } == finish.count)
    }

    @Test func separateWorkoutsAtTheSameInstantAreStillScoredIndependently() {
        let t = Date(timeIntervalSince1970: 86_400)
        let a = Session(
            workoutID: UUID(),
            time: t,
            exerciseID: bench,
            weightType: .barbell,
            sets: [LoggedSet(weight: 110, unit: .kg, reps: 5)]
        )
        let b = Session(
            workoutID: UUID(),
            time: t,
            exerciseID: bench,
            weightType: .barbell,
            sets: [LoggedSet(weight: 110, unit: .kg, reps: 5)]
        )
        let result = prsForEachSession([a, b], weightType: .barbell, options: options)
        #expect(result.count == 2)
        #expect(result[0].prs.count == result[1].prs.count)
        #expect(!result[0].prs.isEmpty)
    }

    // MARK: 2. Singular reps

    @Test func oneRepIsSingular() {
        #expect(formatSetDetail(weight: nil, unit: .kg, reps: 1, durationSeconds: nil) == "1 rep")
        #expect(formatSetDetail(weight: nil, unit: .kg, reps: 2, durationSeconds: nil) == "2 reps")
        #expect(formatSetDetail(weight: 20, unit: .kg, reps: 1, durationSeconds: nil) == "20 kg × 1")
        let one = PersonalRecord(kind: .repsAtWeight, value: 1, weight: 0, reps: 1)
        #expect(HistoryDashboard.text(for: one, unit: .kg) == "1 rep")
        let two = PersonalRecord(kind: .repsAtWeight, value: 2, weight: 0, reps: 2)
        #expect(HistoryDashboard.text(for: two, unit: .kg) == "2 reps")
    }

    // MARK: 3. Gregorian whatever the device calendar

    @Test func dateTextsIgnoreTheCallersCalendarSystem() {
        let when = date(3)
        let old = TestSupport.torontoCalendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 21))
        let past = TestSupport.torontoCalendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 12))
        let identifiers: [Calendar.Identifier] = [.japanese, .buddhist, .islamicUmmAlQura, .republicOfChina, .hebrew]
        for identifier in identifiers {
            var calendar = Calendar(identifier: identifier)
            calendar.timeZone = TimeZone(identifier: "America/Toronto") ?? .gmt
            calendar.firstWeekday = 2
            #expect(HistoryList.monthTitle(when, calendar: calendar) == "November 2026", "\(identifier)")
            #expect(CalendarFormatting.monthDayYear(when, calendar: calendar) == "Nov 3, 2026", "\(identifier)")
            #expect(CalendarFormatting.timeOfDay(when, calendar: calendar) == "10:00 AM", "\(identifier)")
            #expect(
                WorkoutDetail.dateText(when, calendar: calendar, now: date(4)) == "Tuesday, Nov 3 · 10:00 AM",
                "\(identifier)"
            )
            #expect(
                HistoryList.dateText(old ?? .distantPast, now: date(4), calendar: calendar)
                    == "Wednesday, Dec 31, 2025",
                "\(identifier)"
            )
            #expect(
                TemplateCardSummary.relativeText(past ?? .distantPast, now: date(3), calendar: calendar)
                    == "Jan 5, 2026",
                "\(identifier)"
            )
        }
    }
}
