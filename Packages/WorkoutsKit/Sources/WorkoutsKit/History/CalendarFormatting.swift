import Foundation

/// The kit's fixed-pattern date texts, built from `Date.VerbatimFormatStyle` instead of a `DateFormatter` per call.
/// Two families: `en_US_POSIX` texts on the Gregorian calendar (stable identifiers and labels, only the time zone follows
/// the caller), and `en_US` texts that follow the caller's whole calendar.
public nonisolated enum CalendarFormatting {
    // MARK: en_US_POSIX, Gregorian, the caller's time zone

    /// `10/26`: month and day, no padding.
    public static func monthDay(_ date: Date, calendar: Calendar) -> String {
        posix(monthDayFormat, calendar).format(date)
    }

    /// `2026-11-03`: the day identifier.
    public static func isoDay(_ date: Date, calendar: Calendar) -> String {
        posix(isoDayFormat, calendar).format(date)
    }

    /// `Tuesday, November 3`.
    public static func weekdayMonthDay(_ date: Date, calendar: Calendar) -> String {
        posix(weekdayMonthDayFormat, calendar).format(date)
    }

    /// `November 2026`.
    public static func monthYear(_ date: Date, calendar: Calendar) -> String {
        posix(monthYearFormat, calendar).format(date)
    }

    // MARK: en_US, the caller's calendar and time zone

    /// `10:05 AM` / `9:30 PM`.
    public static func timeOfDay(_ date: Date, calendar: Calendar) -> String {
        localized(timeOfDayFormat, calendar).format(date)
    }

    /// `Jul 4, 2026`.
    public static func monthDayYear(_ date: Date, calendar: Calendar) -> String {
        localized(monthDayYearFormat, calendar).format(date)
    }

    // MARK: Styles

    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let usLocale = Locale(identifier: "en_US")

    private static let monthDayFormat = Date.VerbatimFormatStyle(
        format: "\(month: .defaultDigits)/\(day: .defaultDigits)",
        locale: posixLocale,
        timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
    )
    private static let isoDayFormat = Date.VerbatimFormatStyle(
        format: "\(year: .padded(4))-\(month: .twoDigits)-\(day: .twoDigits)",
        locale: posixLocale,
        timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
    )
    private static let weekdayMonthDayFormat = Date.VerbatimFormatStyle(
        format: "\(weekday: .wide), \(month: .wide) \(day: .defaultDigits)",
        locale: posixLocale,
        timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
    )
    private static let monthYearFormat = Date.VerbatimFormatStyle(
        format: "\(month: .wide) \(year: .padded(4))",
        locale: posixLocale,
        timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
    )
    private static let timeOfDayFormat = Date.VerbatimFormatStyle(
        format:
            "\(hour: .defaultDigits(clock: .twelveHour, hourCycle: .oneBased)):\(minute: .twoDigits) \(dayPeriod: .standard(.abbreviated))",
        locale: usLocale,
        timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
    )
    private static let monthDayYearFormat = Date.VerbatimFormatStyle(
        format: "\(month: .abbreviated) \(day: .defaultDigits), \(year: .padded(4))",
        locale: usLocale,
        timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
    )

    /// Gregorian whatever the caller's calendar; only its time zone is used.
    private static func posix(_ style: Date.VerbatimFormatStyle, _ calendar: Calendar) -> Date.VerbatimFormatStyle {
        var style = style
        style.timeZone = calendar.timeZone
        return style
    }

    private static func localized(_ style: Date.VerbatimFormatStyle, _ calendar: Calendar) -> Date.VerbatimFormatStyle {
        var style = style
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }
}
