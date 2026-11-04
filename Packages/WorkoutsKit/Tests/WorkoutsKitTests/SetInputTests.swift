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

    @Test func previousText() {
        let lifted = PreviousSet(weight: 60, reps: 8)
        #expect(SetInputFormat.previousText(lifted, unit: .kg) == "60 kg × 8")
        #expect(SetInputFormat.previousText(lifted, unit: .lb, showsWeight: false) == "8 reps")
        #expect(SetInputFormat.previousText(PreviousSet(weight: 20, durationSeconds: 45), unit: .kg) == "20 kg × 45 s")
        #expect(SetInputFormat.previousText(PreviousSet(), unit: .kg) == nil)
        #expect(SetInputFormat.previousText(nil, unit: .kg) == nil)
    }
}
