import Testing

@testable import WorkoutsKit

struct ElapsedFormatTests {
    @Test func underAnHourIsMinutesAndSeconds() {
        #expect(ElapsedFormat.string(seconds: 0) == "0:00")
        #expect(ElapsedFormat.string(seconds: 5) == "0:05")
        #expect(ElapsedFormat.string(seconds: 65) == "1:05")
        #expect(ElapsedFormat.string(seconds: 3599) == "59:59")
    }

    @Test func fromOneHourAddsHours() {
        #expect(ElapsedFormat.string(seconds: 3600) == "1:00:00")
        #expect(ElapsedFormat.string(seconds: 3725) == "1:02:05")
        #expect(ElapsedFormat.string(seconds: 36_000) == "10:00:00")
    }

    @Test func negativeClampsToZero() {
        #expect(ElapsedFormat.string(seconds: -30) == "0:00")
    }
}
