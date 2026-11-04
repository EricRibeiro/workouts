import Foundation

/// Pure month-grid logic for the History Calendar sheet (`docs/port/screens/history.md` section 2, "Calendar"; PLAN 5.4).
/// Weeks start Monday whatever the locale, and every day is cut in the injected calendar's time zone.
/// A calendar day by year, month and day, in whatever time zone the caller's calendar cuts days.
public nonisolated struct CalendarDay: Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}

public nonisolated enum CalendarMonth {
    /// The column headers, Monday first.
    public static let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]

    /// The month containing `month` as Monday-first rows of seven: `nil` pads the days of the neighbouring months, and
    /// each real day is the start of that day in `calendar`'s time zone. Empty if the calendar cannot build the month.
    public static func monthGrid(for month: Date, calendar: Calendar) -> [[Date?]] {
        let calendar = mondayFirst(calendar)
        guard let interval = calendar.dateInterval(of: .month, for: month),
            let days = calendar.range(of: .day, in: .month, for: month)
        else { return [] }
        let first = interval.start
        // Monday = 0 ... Sunday = 6.
        let leading = (calendar.component(.weekday, from: first) + 5) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<days.count {
            cells.append(calendar.date(byAdding: .day, value: offset, to: first).map { calendar.startOfDay(for: $0) })
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// The year, month and day of `date` in `calendar`: the key of the day lookups below.
    public static func day(of date: Date, calendar: Calendar) -> CalendarDay {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return CalendarDay(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// The days (year, month, day in `calendar`) that have at least one of `dates`.
    public static func workoutDays(_ dates: [Date], calendar: Calendar) -> Set<CalendarDay> {
        Set(dates.map { day(of: $0, calendar: calendar) })
    }

    /// How many of `dates` fall on each day.
    public static func workoutCounts(_ dates: [Date], calendar: Calendar) -> [CalendarDay: Int] {
        dates.reduce(into: [:]) { $0[day(of: $1, calendar: calendar), default: 0] += 1 }
    }

    /// `November 2026`.
    public static func title(for month: Date, calendar: Calendar) -> String {
        format(month, "LLLL yyyy", calendar: calendar)
    }

    /// `month` moved by `months` whole months (negative goes back), landing on the first of that month.
    public static func shift(_ month: Date, by months: Int, calendar: Calendar) -> Date {
        let calendar = mondayFirst(calendar)
        let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
        return calendar.date(byAdding: .month, value: months, to: start) ?? start
    }

    /// `2026-11-03`, the suffix of a day's accessibility identifier.
    public static func identifier(for date: Date, calendar: Calendar) -> String {
        format(date, "yyyy-MM-dd", calendar: calendar)
    }

    /// `Tuesday, November 3, 1 workout` / `Wednesday, November 4` for an empty day.
    public static func accessibilityLabel(for date: Date, workouts: Int, calendar: Calendar) -> String {
        let text = format(date, "EEEE, MMMM d", calendar: calendar)
        switch workouts {
        case ..<1: return text
        case 1: return "\(text), 1 workout"
        default: return "\(text), \(workouts) workouts"
        }
    }

    private static func format(_ date: Date, _ pattern: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
