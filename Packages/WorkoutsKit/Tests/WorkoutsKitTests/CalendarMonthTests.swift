import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct CalendarMonthTests {
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        calendar.firstWeekday = 1  // the grid must override this
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, zone: String = "UTC") -> Date {
        calendar(zone).date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private func days(_ grid: [[Date?]], zone: String = "UTC") -> [Int?] {
        let calendar = calendar(zone)
        return grid.flatMap { $0 }.map { $0.map { calendar.component(.day, from: $0) } }
    }

    @Test func novemberStartsOnSunday() {
        // 2026-11-01 is a Sunday: six leading blanks on a Monday-first grid.
        let grid = CalendarMonth.monthGrid(for: date(2026, 11, 14), calendar: calendar())
        #expect(grid.count == 6)
        #expect(grid.allSatisfy { $0.count == 7 })
        let flat = days(grid)
        #expect(flat.prefix(6).allSatisfy { $0 == nil })
        #expect(flat[6] == 1)
        #expect(flat.compactMap { $0 } == Array(1...30))
        #expect(flat.suffix(5).allSatisfy { $0 == nil })
    }

    @Test func februaryStartingOnMondayFitsFourRows() {
        // 2027-02-01 is a Monday and the month has 28 days: exactly four full rows, no padding.
        let grid = CalendarMonth.monthGrid(for: date(2027, 2, 10), calendar: calendar())
        #expect(grid.count == 4)
        #expect(days(grid).compactMap { $0 } == Array(1...28))
        #expect(!days(grid).contains { $0 == nil })
    }

    @Test func leapFebruaryHas29Days() {
        let grid = CalendarMonth.monthGrid(for: date(2028, 2, 1), calendar: calendar())
        #expect(days(grid).compactMap { $0 }.count == 29)
        // 2028-02-01 is a Tuesday.
        #expect(days(grid).prefix(2).map { $0 } == [nil, 1])
    }

    @Test func daysAreStartsOfDayInTheCalendarZone() {
        let toronto = calendar("America/Toronto")
        let grid = CalendarMonth.monthGrid(for: date(2026, 11, 14, zone: "America/Toronto"), calendar: toronto)
        for cell in grid.flatMap({ $0 }).compactMap({ $0 }) {
            #expect(cell == toronto.startOfDay(for: cell))
        }
    }

    @Test func dstMonthInTorontoKeepsEveryDayOnce() {
        // DST ends 2026-11-01 (a 25-hour day) in Toronto.
        let toronto = calendar("America/Toronto")
        let grid = CalendarMonth.monthGrid(for: date(2026, 11, 20, zone: "America/Toronto"), calendar: toronto)
        #expect(days(grid, zone: "America/Toronto").compactMap { $0 } == Array(1...30))
        // And the spring-forward month (2026-03-08).
        let march = CalendarMonth.monthGrid(for: date(2026, 3, 20, zone: "America/Toronto"), calendar: toronto)
        #expect(days(march, zone: "America/Toronto").compactMap { $0 } == Array(1...31))
    }

    @Test func workoutDaysCutInTheCalendarZone() {
        let toronto = calendar("America/Toronto")
        // 23:30 on Nov 3 in Toronto is already Nov 4 in UTC.
        let late = date(2026, 11, 3, 23, zone: "America/Toronto").addingTimeInterval(30 * 60)
        let set = CalendarMonth.workoutDays([late, date(2026, 11, 5)], calendar: toronto)
        #expect(set.contains(CalendarDay(year: 2026, month: 11, day: 3)))
        #expect(!set.contains(CalendarDay(year: 2026, month: 11, day: 4)))
        let utc = CalendarMonth.workoutDays([late], calendar: calendar())
        #expect(utc == [CalendarDay(year: 2026, month: 11, day: 4)])
    }

    @Test func countsPerDay() {
        let counts = CalendarMonth.workoutCounts(
            [date(2026, 11, 3, 8), date(2026, 11, 3, 18), date(2026, 11, 4)],
            calendar: calendar()
        )
        #expect(counts[CalendarDay(year: 2026, month: 11, day: 3)] == 2)
        #expect(counts[CalendarDay(year: 2026, month: 11, day: 4)] == 1)
    }

    @Test func titleAndShift() {
        let november = date(2026, 11, 14)
        #expect(CalendarMonth.title(for: november, calendar: calendar()) == "November 2026")
        let december = CalendarMonth.shift(november, by: 1, calendar: calendar())
        #expect(CalendarMonth.title(for: december, calendar: calendar()) == "December 2026")
        let back = CalendarMonth.shift(date(2026, 1, 31), by: -1, calendar: calendar())
        #expect(CalendarMonth.title(for: back, calendar: calendar()) == "December 2025")
        // Shifting from the 31st never skips a short month.
        let feb = CalendarMonth.shift(date(2026, 1, 31), by: 1, calendar: calendar())
        #expect(CalendarMonth.title(for: feb, calendar: calendar()) == "February 2026")
    }

    @Test func identifierAndLabels() {
        let day = date(2026, 11, 3)
        #expect(CalendarMonth.identifier(for: day, calendar: calendar()) == "2026-11-03")
        #expect(
            CalendarMonth.accessibilityLabel(for: day, workouts: 1, calendar: calendar())
                == "Tuesday, November 3, 1 workout"
        )
        #expect(
            CalendarMonth.accessibilityLabel(for: day, workouts: 2, calendar: calendar())
                == "Tuesday, November 3, 2 workouts"
        )
        #expect(CalendarMonth.accessibilityLabel(for: day, workouts: 0, calendar: calendar()) == "Tuesday, November 3")
        #expect(CalendarMonth.weekdayInitials.joined() == "MTWTFSS")
    }
}
