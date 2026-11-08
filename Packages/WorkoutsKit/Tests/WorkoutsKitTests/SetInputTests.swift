import Testing

@testable import WorkoutsKit

@Suite struct SetInputTests {
    @Test func kindCycleOrder() {
        #expect(SetInputFormat.nextKind(after: .normal) == .warmup)
        #expect(SetInputFormat.nextKind(after: .warmup) == .drop)
        #expect(SetInputFormat.nextKind(after: .drop) == .failure)
        #expect(SetInputFormat.nextKind(after: .failure) == .normal)
    }

    @Test func labels() {
        #expect(SetInputFormat.setLabel(number: 3, kind: .normal) == "3")
        #expect(SetInputFormat.setLabel(number: 3, kind: .warmup) == "W")
        #expect(SetInputFormat.setLabel(number: 3, kind: .drop) == "D")
        #expect(SetInputFormat.setLabel(number: 3, kind: .failure) == "F")
        #expect(SetInputFormat.setAccessibilityLabel(number: 2, kind: .normal) == "Set 2")
        #expect(SetInputFormat.setAccessibilityLabel(number: 1, kind: .warmup) == "Set 1, warm-up")
    }

    @Test(arguments: [("27.5", 27.5), ("27,5", 27.5), (" 100 ", 100), ("0", 0), (".5", 0.5), ("12.", 12)])
    func parsesWeight(text: String, expected: Double) {
        #expect(SetInputFormat.parseWeight(text) == expected)
    }

    @Test func weightEdgeCases() {
        #expect(SetInputFormat.parseWeight("") == nil)
        #expect(SetInputFormat.parseWeight("   ") == nil)
        #expect(SetInputFormat.parseWeight("abc") == nil)
        #expect(SetInputFormat.parseWeight("1.2.3") == nil)
        #expect(SetInputFormat.parseWeight("-5") == 0)
        #expect(SetInputFormat.parseWeight("22.256") == 22.26)
        #expect(SetInputFormat.parseWeight("22.254") == 22.25)
        #expect(SetInputFormat.parseWeight("inf") == nil)
    }

    @Test func weightRejectsExponentHexAndAbsurdValues() {
        for text in [
            "1e307", "1e3", "1E2", "0x10", "0b1", "nan", "-inf", "1_000", "٣", "--5", "+-5", ".", "-", "10000.01",
            "99999",
        ] {
            #expect(SetInputFormat.parseWeight(text) == nil, "\(text)")
        }
        #expect(SetInputFormat.parseWeight("10000") == 10_000)
        #expect(SetInputFormat.parseWeight("+5") == 5)
    }

    @Test func countRejectsExponentAndHex() {
        for text in ["1e3", "0x10", "inf", "nan", "1.2.3", "."] {
            #expect(SetInputFormat.parseCount(text) == nil, "\(text)")
        }
    }

    @Test func parsesCount() {
        #expect(SetInputFormat.parseCount("8") == 8)
        #expect(SetInputFormat.parseCount(" 12 ") == 12)
        #expect(SetInputFormat.parseCount("") == nil)
        #expect(SetInputFormat.parseCount("x") == nil)
        #expect(SetInputFormat.parseCount("-3") == 0)
        #expect(SetInputFormat.parseCount("7,6") == 8)
        #expect(SetInputFormat.parseCount("99999999999") == 1_000_000)
    }

    @Test func fieldText() {
        #expect(SetInputFormat.weightText(nil) == "")
        #expect(SetInputFormat.weightText(60) == "60")
        #expect(SetInputFormat.weightText(27.5) == "27.5")
        #expect(SetInputFormat.weightText(-1) == "0")
        #expect(SetInputFormat.countText(nil) == "")
        #expect(SetInputFormat.countText(8) == "8")
    }

    @Test(
        arguments: [
            (nil, ""), (0, "0:00"), (30, "0:30"), (59, "0:59"), (60, "1:00"), (61, "1:01"), (80, "1:20"),
            (725, "12:05"), (3599, "59:59"), (3600, "1:00:00"), (3725, "1:02:05"), (-5, "0:00"),
        ] as [(Int?, String)]
    )
    func durationText(seconds: Int?, expected: String) {
        #expect(SetInputFormat.durationText(seconds) == expected)
    }

    @Test(
        arguments: [
            (nil, ""), (0, "0"), (30, "30"), (59, "59"), (60, "100"), (61, "101"), (90, "130"), (725, "1205"),
            (3600, "6000"),
        ] as [(Int?, String)]
    )
    func durationDigits(seconds: Int?, expected: String) {
        #expect(SetInputFormat.durationDigits(seconds) == expected)
    }

    @Test(
        arguments: [
            ("", nil), ("ab", nil), ("0", 0), ("5", 5), ("59", 59), ("60", 60), ("61", 61), ("100", 60), ("130", 90),
            ("190", 150), ("1305", 785), ("6000", 3600), ("1:30", 90), ("a1b3c0", 90), ("005", 5),
        ] as [(String, Int?)]
    )
    func parseDurationDigits(text: String, expected: Int?) {
        #expect(SetInputFormat.parseDurationDigits(text) == expected)
    }

    @Test(
        arguments: [
            ("", nil), ("ab", nil), ("1:30", 90), ("0:45", 45), ("12:05", 725), ("1:00:00", 3600), ("1:02:05", 3725),
            ("130", 90), ("45", 45), ("1:", 1),
        ] as [(String, Int?)]
    )
    func parseDurationText(text: String, expected: Int?) {
        #expect(SetInputFormat.parseDurationText(text) == expected)
    }

    @Test(arguments: [
        ("", ""), ("1", "1"), ("13", "13"), ("130", "1:30"), ("1305", "13:05"), ("0305", "3:05"), ("005", "0:05"),
        ("ab", ""), ("1:30", "1:30"), ("12345", "123:45"),
    ])
    func durationEntryText(digits: String, expected: String) {
        #expect(SetInputFormat.durationEntryText(digits) == expected)
    }

    @Test func durationDigitsRoundTrip() {
        for seconds in [0, 5, 30, 59, 60, 61, 90, 725, 3599, 3600, 5400] {
            #expect(SetInputFormat.parseDurationDigits(SetInputFormat.durationDigits(seconds)) == seconds)
        }
    }

    @Test func previousText() {
        let lifted = PreviousSet(weight: 60, reps: 8)
        #expect(SetInputFormat.previousText(lifted, unit: .kg) == "60 kg × 8")
        #expect(SetInputFormat.previousText(lifted, unit: .lb, showsWeight: false) == "8 reps")
        #expect(SetInputFormat.previousText(PreviousSet(weight: 20, durationSeconds: 45), unit: .kg) == "20 kg × 0:45")
        #expect(SetInputFormat.previousText(PreviousSet(), unit: .kg) == nil)
        #expect(SetInputFormat.previousText(nil, unit: .kg) == nil)
    }
}
