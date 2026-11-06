import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct CalendarFormattingTests {
    private static let zones = [
        "America/Toronto", "UTC", "Asia/Tokyo", "Pacific/Kiritimati", "Pacific/Pago_Pago", "Asia/Kolkata",
    ]

    private static func calendar(_ identifier: Calendar.Identifier = .gregorian, zone: String) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    /// The `DateFormatter` the helper replaced, kept as the reference.
    private static func reference(_ pattern: String, _ date: Date, locale: String, calendar: Calendar?, zone: TimeZone)
        -> String
    {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.calendar = calendar ?? Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// About every 41 hours over 12 years, which crosses every month, year and DST edge.
    private static let dates: [Date] = stride(from: 0, to: 12 * 365 * 24 * 3_600, by: 41 * 3_600).map {
        Date(timeIntervalSince1970: 1_577_836_800 + Double($0))
    }

    @Test func examples() {
        let toronto = Self.calendar(zone: "America/Toronto")
        // 2026-11-03 21:30 in Toronto is already 2026-11-04 in UTC.
        let evening = Date(timeIntervalSince1970: 1_793_759_400)
        #expect(CalendarFormatting.monthDay(evening, calendar: toronto) == "11/3")
        #expect(CalendarFormatting.isoDay(evening, calendar: toronto) == "2026-11-03")
        #expect(CalendarFormatting.weekdayMonthDay(evening, calendar: toronto) == "Tuesday, November 3")
        #expect(CalendarFormatting.monthYear(evening, calendar: toronto) == "November 2026")
        #expect(CalendarFormatting.timeOfDay(evening, calendar: toronto) == "9:30 PM")
        #expect(CalendarFormatting.monthDayYear(evening, calendar: toronto) == "Nov 3, 2026")
        #expect(CalendarFormatting.isoDay(evening, calendar: Self.calendar(zone: "UTC")) == "2026-11-04")
    }

    @Test func posixTextsMatchTheDateFormatter() {
        for zone in Self.zones {
            let calendar = Self.calendar(zone: zone)
            for date in Self.dates {
                let tz = calendar.timeZone
                #expect(
                    CalendarFormatting.monthDay(date, calendar: calendar)
                        == Self.reference("M/d", date, locale: "en_US_POSIX", calendar: nil, zone: tz),
                    "\(zone) \(date)"
                )
                #expect(
                    CalendarFormatting.isoDay(date, calendar: calendar)
                        == Self.reference("yyyy-MM-dd", date, locale: "en_US_POSIX", calendar: nil, zone: tz),
                    "\(zone) \(date)"
                )
                #expect(
                    CalendarFormatting.monthYear(date, calendar: calendar)
                        == Self.reference("LLLL yyyy", date, locale: "en_US_POSIX", calendar: nil, zone: tz),
                    "\(zone) \(date)"
                )
                #expect(
                    CalendarFormatting.weekdayMonthDay(date, calendar: calendar)
                        == Self.reference("EEEE, MMMM d", date, locale: "en_US_POSIX", calendar: nil, zone: tz),
                    "\(zone) \(date)"
                )
            }
        }
    }

    @Test func posixTextsIgnoreTheCallersCalendarIdentifier() {
        let buddhist = Self.calendar(.buddhist, zone: "Asia/Tokyo")
        let gregorian = Self.calendar(zone: "Asia/Tokyo")
        for date in Self.dates.prefix(200) {
            #expect(
                CalendarFormatting.isoDay(date, calendar: buddhist)
                    == CalendarFormatting.isoDay(date, calendar: gregorian)
            )
        }
    }

    @Test func localizedTextsMatchTheDateFormatter() {
        for zone in Self.zones {
            let calendar = Self.calendar(zone: zone)
            for date in Self.dates {
                let tz = calendar.timeZone
                #expect(
                    CalendarFormatting.timeOfDay(date, calendar: calendar)
                        == Self.reference("h:mm a", date, locale: "en_US", calendar: calendar, zone: tz),
                    "\(zone) \(date)"
                )
                #expect(
                    CalendarFormatting.monthDayYear(date, calendar: calendar)
                        == Self.reference("MMM d, yyyy", date, locale: "en_US", calendar: calendar, zone: tz),
                    "\(zone) \(date)"
                )
            }
        }
    }

    @Test(arguments: [Calendar.Identifier.buddhist, .japanese, .iso8601])
    func localizedTextsStayGregorianInOtherCalendars(identifier: Calendar.Identifier) {
        // English text is Gregorian whatever the device calendar; only the time zone follows the caller.
        let calendar = Self.calendar(identifier, zone: "America/Toronto")
        for date in Self.dates.prefix(300) {
            #expect(
                CalendarFormatting.timeOfDay(date, calendar: calendar)
                    == Self.reference("h:mm a", date, locale: "en_US", calendar: nil, zone: calendar.timeZone)
            )
            #expect(
                CalendarFormatting.monthDayYear(date, calendar: calendar)
                    == Self.reference("MMM d, yyyy", date, locale: "en_US", calendar: nil, zone: calendar.timeZone)
            )
        }
    }
}
