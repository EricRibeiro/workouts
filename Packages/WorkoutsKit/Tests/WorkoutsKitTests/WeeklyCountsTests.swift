import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct WeeklyCountsTests {
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        calendar.firstWeekday = 1  // the function must override this
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 12,
        _ minute: Int = 0,
        zone: String = "UTC"
    ) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar(zone).date(from: parts) ?? .distantPast
    }

    @Test func zeroFillsEightWeeksCurrentLast() {
        // Wed 2026-11-04. The Mondays are 09-14 ... 11-02.
        let counts = weeklyCounts(workouts: [], calendar: calendar(), now: date(2026, 11, 4))
        #expect(counts.count == 8)
        #expect(counts.allSatisfy { $0.count == 0 })
        #expect(counts.first?.weekStart == date(2026, 9, 14, 0))
        #expect(counts.last?.weekStart == date(2026, 11, 2, 0))
    }

    @Test func countsLandInTheirWeek() {
        let workouts = [
            date(2026, 11, 3), date(2026, 11, 4), date(2026, 11, 2, 6),  // this week
            date(2026, 10, 26, 8),  // last week
            date(2026, 9, 14, 8),  // oldest shown
            date(2026, 9, 13, 23),  // a week too old
        ]
        let counts = weeklyCounts(workouts: workouts, calendar: calendar(), now: date(2026, 11, 4))
        #expect(counts.map(\.count) == [1, 0, 0, 0, 0, 0, 1, 3])
    }

    @Test func mondayStartsTheWeekAndSundayEndsIt() {
        let now = date(2026, 11, 8, 20)  // Sunday, still the week of 11-02
        let workouts = [date(2026, 11, 2, 0, 0), date(2026, 11, 1, 23, 59)]
        let counts = weeklyCounts(workouts: workouts, calendar: calendar(), now: now)
        #expect(counts.last?.weekStart == date(2026, 11, 2, 0))
        #expect(counts.suffix(2).map(\.count) == [1, 1])
    }

    @Test func fewerWeeks() {
        let counts = weeklyCounts(workouts: [], calendar: calendar(), weeks: 3, now: date(2026, 11, 4))
        #expect(counts.count == 3)
        #expect(weeklyCounts(workouts: [], calendar: calendar(), weeks: 0, now: .now).isEmpty)
    }

    @Test func torontoDSTBoundarySplitsSundayNightFromMondayMorning() {
        // DST ended Sunday 2026-11-01 at 02:00 in America/Toronto, so the week of 10-26 is 169 hours long.
        let zone = "America/Toronto"
        let sunday = date(2026, 11, 1, 23, 30, zone: zone)
        let monday = date(2026, 11, 2, 0, 30, zone: zone)
        let now = date(2026, 11, 3, 9, zone: zone)
        let counts = weeklyCounts(workouts: [sunday, monday], calendar: calendar(zone), now: now)
        #expect(counts.count == 8)
        #expect(counts[6].weekStart == date(2026, 10, 26, 0, zone: zone))
        #expect(counts[7].weekStart == date(2026, 11, 2, 0, zone: zone))
        #expect(counts[6].count == 1)
        #expect(counts[7].count == 1)
        // Every week starts on a local-midnight Monday, before and after the change.
        let toronto = calendar(zone)
        #expect(counts.allSatisfy { toronto.component(.hour, from: $0.weekStart) == 0 })
        #expect(counts.allSatisfy { toronto.component(.weekday, from: $0.weekStart) == 2 })
    }

    @Test func theCalendarsTimeZoneDecidesTheWeek() {
        // Sun 2026-11-01 23:30 Toronto is Mon 2026-11-02 04:30 UTC: another week in UTC.
        let instant = date(2026, 11, 1, 23, 30, zone: "America/Toronto")
        let now = date(2026, 11, 3)
        let toronto = weeklyCounts(workouts: [instant], calendar: calendar("America/Toronto"), now: now)
        let utc = weeklyCounts(workouts: [instant], calendar: calendar("UTC"), now: now)
        #expect(toronto.map(\.count) == [0, 0, 0, 0, 0, 0, 1, 0])
        #expect(utc.map(\.count) == [0, 0, 0, 0, 0, 0, 0, 1])
    }

    @Test func axisTopIsOneStepOverTheHigherOfGoalAndBusiestWeek() {
        let counts = [WeekCount(weekStart: .now, count: 2), WeekCount(weekStart: .now, count: 5)]
        #expect(axisTop(counts: counts, goal: 3) == 6)
        #expect(axisTop(counts: counts, goal: 7) == 8)
        #expect(axisTop(counts: [], goal: 3) == 4)
        #expect(axisTop(counts: [WeekCount(weekStart: .now, count: 0)], goal: 1) == 2)
    }

    @Test func labelIsTheMondayAsMonthSlashDay() {
        let toronto = calendar("America/Toronto")
        #expect(weekLabel(date(2026, 10, 26, 0, zone: "America/Toronto"), calendar: toronto) == "10/26")
        #expect(weekLabel(date(2026, 11, 2, 0, zone: "America/Toronto"), calendar: toronto) == "11/2")
    }

    @Test func nonGregorianDeviceCalendarStillBucketsInGregorianMonthsAndWeeks() {
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let now = date(2026, 11, 4)
        // Weeks: same Mondays as the Gregorian calendar.
        let counts = weeklyCounts(workouts: [date(2026, 11, 3)], calendar: hebrew, now: now)
        #expect(counts.last?.weekStart == date(2026, 11, 2, 0))
        #expect(counts.last?.count == 1)
        // Months: HistoryList and the Calendar sheet cut Gregorian months (Hebrew months would start mid-month).
        #expect(HistoryList.monthStart(of: date(2026, 10, 20), calendar: hebrew) == date(2026, 10, 1, 0))
        #expect(HistoryList.monthStart(of: date(2026, 10, 3), calendar: hebrew) == date(2026, 10, 1, 0))
        let grid = CalendarMonth.monthGrid(for: date(2026, 11, 15), calendar: hebrew).flatMap { $0 }.compactMap { $0 }
        #expect(grid.contains(date(2026, 11, 1, 0)))
        #expect(!grid.contains(date(2026, 10, 31, 0)))
        #expect(ChartRange.month.start(now: date(2026, 3, 31), calendar: hebrew) == date(2026, 2, 28))
    }
}
