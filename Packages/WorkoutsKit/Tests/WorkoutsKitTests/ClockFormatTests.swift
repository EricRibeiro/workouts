import Testing

@testable import WorkoutsKit

struct ClockFormatTests {
    @Test func clockUnderAnHourIsMinutesAndSeconds() {
        #expect(ClockFormat.clock(seconds: 0) == "0:00")
        #expect(ClockFormat.clock(seconds: 5) == "0:05")
        #expect(ClockFormat.clock(seconds: 65) == "1:05")
        #expect(ClockFormat.clock(seconds: 39 * 60 + 53) == "39:53")
        #expect(ClockFormat.clock(seconds: 3599) == "59:59")
    }

    @Test func clockFromAnHourAddsHours() {
        #expect(ClockFormat.clock(seconds: 3600) == "1:00:00")
        #expect(ClockFormat.clock(seconds: 3725) == "1:02:05")
        #expect(ClockFormat.clock(seconds: 3600 + 5 * 60 + 9) == "1:05:09")
        #expect(ClockFormat.clock(seconds: 36_000) == "10:00:00")
    }

    @Test func clockClampsNegativeToZero() {
        #expect(ClockFormat.clock(seconds: -30) == "0:00")
        #expect(ClockFormat.clock(seconds: -4.0) == "0:00")
    }

    @Test func clockRoundsFractionalSeconds() {
        #expect(ClockFormat.clock(seconds: 69.6) == "1:10")
        #expect(ClockFormat.clock(seconds: 70.4) == "1:10")
        #expect(ClockFormat.clock(seconds: 3600.0 + 5 * 60 + 9) == "1:05:09")
    }

    @Test func compactReadsSecondsThenMinutes() {
        #expect(ClockFormat.compact(seconds: 0) == "0 s")
        #expect(ClockFormat.compact(seconds: 45) == "45 s")
        #expect(ClockFormat.compact(seconds: 60) == "1:00")
        #expect(ClockFormat.compact(seconds: 90) == "1:30")
        #expect(ClockFormat.compact(seconds: 605) == "10:05")
        #expect(ClockFormat.compact(seconds: -5) == "0 s")
    }
}
