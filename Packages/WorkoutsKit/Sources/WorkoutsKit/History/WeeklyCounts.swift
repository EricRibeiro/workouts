import Foundation

/// Workouts started in one Monday-first week (`docs/port/screens/history.md` section 2, "Weekly chart").
public nonisolated struct WeekCount: Hashable, Sendable {
    /// Start of the Monday, in the calendar's time zone.
    public var weekStart: Date
    public var count: Int

    public init(weekStart: Date, count: Int) {
        self.weekStart = weekStart
        self.count = count
    }
}

/// A Gregorian calendar in `calendar`'s time zone. History cuts months and weeks in Gregorian whatever calendar the
/// device uses (Hebrew, Islamic, ...), because every title is formatted Gregorian (`CalendarFormatting`).
nonisolated func gregorian(like calendar: Calendar) -> Calendar {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    return gregorian
}

/// A Gregorian calendar in `calendar`'s time zone with Monday as the first weekday, so `.weekOfYear` boundaries are
/// Monday to Sunday whatever the locale or device calendar.
nonisolated func mondayFirst(_ calendar: Calendar) -> Calendar {
    var calendar = gregorian(like: calendar)
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
}

/// The last `weeks` Monday-first weeks ending with the one containing `now`, oldest first and zero-filled, with the
/// number of `workouts` (finished workouts' start dates) in each. Weeks are cut in `calendar`'s time zone, so a
/// workout at 23:30 Sunday and one at 00:30 Monday fall in different weeks even across a DST change.
public nonisolated func weeklyCounts(
    workouts: [Date],
    calendar: Calendar,
    weeks: Int = 8,
    now: Date
) -> [WeekCount] {
    guard weeks > 0 else { return [] }
    let calendar = mondayFirst(calendar)
    guard let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }

    var starts: [Date] = []
    for back in stride(from: weeks - 1, through: 0, by: -1) {
        if let start = calendar.date(byAdding: .weekOfYear, value: -back, to: current) {
            starts.append(start)
        }
    }

    var counts: [Date: Int] = [:]
    for workout in workouts {
        if let start = calendar.dateInterval(of: .weekOfYear, for: workout)?.start {
            counts[start, default: 0] += 1
        }
    }
    return starts.map { WeekCount(weekStart: $0, count: counts[$0] ?? 0) }
}

/// The top of the chart's y axis: one whole workout of headroom over the goal or the busiest week, whichever is higher.
public nonisolated func axisTop(counts: [WeekCount], goal: Int) -> Int {
    max(goal, counts.map(\.count).max() ?? 0, 0) + 1
}

/// The x label of a week: its Monday as month/day, such as `10/26`.
public nonisolated func weekLabel(_ weekStart: Date, calendar: Calendar) -> String {
    CalendarFormatting.monthDay(weekStart, calendar: calendar)
}
