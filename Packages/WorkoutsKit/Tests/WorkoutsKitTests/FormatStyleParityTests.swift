import Foundation
import Testing

@testable import WorkoutsKit

/// The History texts are produced with `FormatStyle`s. These tests hold them byte-identical to the `NumberFormatter` and
/// `DateFormatter` configurations they replaced, which stay here only as the reference.
@Suite struct FormatStyleParityTests {
    private static let enUS = Locale(identifier: "en_US")

    private static func referenceNumber(_ configure: (NumberFormatter) -> Void, _ value: Double) -> String? {
        let format = NumberFormatter()
        format.locale = enUS
        format.numberStyle = .decimal
        configure(format)
        return format.string(from: NSNumber(value: value))
    }

    private static func referenceDate(_ pattern: String, _ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = enUS
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private static let values: [Double] = {
        var values: [Double] = [
            0, -0.0, 0.4, 0.5, 1.5, 2.5, 0.005, 0.015, 0.125, 2.675, 117.5, 999.4, 999.5, 1_000, 1_929.125,
            15_420.5, 15_421, 123_456.789, 1_234_567.891, 99_999_999.5, 1e12, -0.4, -0.5, -1.5, -1_234.567,
        ]
        var seed: UInt64 = 42
        for _ in 0..<2_000 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            values.append(Double(seed >> 33) / 1_000.0)
            values.append(Double(seed >> 40) / 8.0)
        }
        return values
    }()

    @Test func volumeTextMatchesTheNumberFormatter() {
        for value in Self.values {
            let reference = Self.referenceNumber(
                {
                    $0.maximumFractionDigits = 0
                    $0.roundingMode = .halfUp
                },
                value
            )
            #expect(HistoryList.volumeText(value, unit: .kg) == "\(reference ?? "0") kg", "volume \(value)")
        }
    }

    @Test func groupedWeightMatchesTheNumberFormatter() {
        for value in Self.values {
            let reference = Self.referenceNumber(
                {
                    $0.usesGroupingSeparator = true
                    $0.minimumFractionDigits = 0
                    $0.maximumFractionDigits = 2
                },
                value
            )
            let expected = reference.map { $0 == "-0" ? "0" : $0 } ?? formatWeight(value)
            #expect(HistoryDashboard.groupedWeight(value) == expected, "weight \(value)")
        }
    }

    @Test func dateTextsMatchTheDateFormatter() {
        let zones = ["America/Toronto", "UTC", "Asia/Tokyo", "Pacific/Kiritimati", "Pacific/Pago_Pago", "Asia/Kolkata"]
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        for zone in zones {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
            // About every 41 hours over 12 years, which also crosses every month, year and DST edge.
            for step in stride(from: 0, to: 12 * 365 * 24 * 3_600, by: 41 * 3_600) {
                let date = Date(timeIntervalSince1970: 1_577_836_800 + Double(step))
                let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
                let pattern = sameYear ? "EEEE, MMM d" : "EEEE, MMM d, yyyy"
                #expect(
                    HistoryList.dateText(date, now: now, calendar: calendar)
                        == Self.referenceDate(pattern, date, calendar: calendar),
                    "\(zone) \(date)"
                )
                #expect(
                    HistoryList.monthTitle(date, calendar: calendar)
                        == Self.referenceDate("LLLL yyyy", date, calendar: calendar),
                    "\(zone) \(date)"
                )
            }
        }
    }

    @Test(arguments: [Calendar.Identifier.buddhist, .japanese, .iso8601])
    func dateTextsFollowOtherCalendarsLikeTheDateFormatter(identifier: Calendar.Identifier) {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: "America/Toronto") ?? .gmt
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        for step in stride(from: 0, to: 4 * 365 * 24 * 3_600, by: 97 * 3_600) {
            let date = Date(timeIntervalSince1970: 1_577_836_800 + Double(step))
            let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
            let pattern = sameYear ? "EEEE, MMM d" : "EEEE, MMM d, yyyy"
            #expect(
                HistoryList.dateText(date, now: now, calendar: calendar)
                    == Self.referenceDate(pattern, date, calendar: calendar)
            )
            #expect(
                HistoryList.monthTitle(date, calendar: calendar)
                    == Self.referenceDate("LLLL yyyy", date, calendar: calendar)
            )
        }
    }
}
