import Foundation
import Testing

@testable import DuoKit

private func reading(_ angle: Double, valid: Bool = true) -> HingeReading {
    HingeReading(angleDegrees: angle, angleValid: valid)
}

/// Serves scripted readings (the last one repeats) and records the windows it was asked for.
private final class Script {
    var readings: [HingeReading]
    private(set) var windows: [Int] = []

    init(_ readings: [HingeReading]) {
        self.readings = readings
    }

    func next(_ window: Int) -> HingeReading {
        windows.append(window)
        return readings.count > 1 ? readings.removeFirst() : readings[0]
    }
}

private func target(_ argument: String) throws -> FoldTarget {
    try #require(FoldTarget.parse(argument))
}

@Suite struct FoldTargetTests {
    @Test func presetsAndAngles() throws {
        #expect(try target("closed").angle == 0)
        #expect(try target("half-open").angle == 130)
        #expect(try target("open").angle == 180)
        #expect(try target("90").pose == .halfOpen)
        #expect(try target("0").pose == .closed)
        #expect(try target("179").pose == .open)
    }

    @Test func rejectsNonsense() {
        for bad in ["", "ajar", "-1", "181", "nan", "inf", "12,5"] { #expect(FoldTarget.parse(bad) == nil) }
    }

    @Test func expectedPanelFollowsThePose() throws {
        #expect(try target("closed").expectedPanel == .outer)
        #expect(try target("open").expectedPanel == .inner)
        #expect(try target("half-open").expectedPanel == .inner)
    }

    @Test func acceptsOnlyValidReadingsInTheCategory() throws {
        #expect(try target("open").accepts(reading(179)))
        #expect(try !target("open").accepts(reading(120)))
        #expect(try !target("open").accepts(reading(180, valid: false)))
        #expect(try target("half-open").accepts(reading(97)))
        // An explicit angle is a category too: the simulator settles at its own angle (130 holds near 123).
        #expect(try target("100").accepts(reading(123.3)))
        #expect(try !target("100").accepts(reading(180)))
        #expect(try !target("100").accepts(reading(0)))
    }
}

@Suite struct PoseVerifierTests {
    @Test func closedIsReachedOnTheFirstRead() throws {
        let script = Script([reading(0)])
        let result = try PoseVerifier.verify(target: target("closed"), read: script.next)
        #expect(result.reached)
        #expect(result.reads.count == 1)
        #expect(script.windows == [0])
    }

    @Test func aSlowSettleTakesSeveralReadsWithLaterWindows() throws {
        let script = Script([reading(0), reading(40), reading(120), reading(180)])
        let result = try PoseVerifier.verify(target: target("open"), read: script.next)
        #expect(result.reached)
        #expect(result.reads.count == 4)
        #expect(script.windows == [0, 1000, 1000, 1000])
    }

    @Test func neverSettlingFailsAfterEightReads() throws {
        let script = Script([reading(0), reading(10)])
        let result = try PoseVerifier.verify(target: target("open"), read: script.next)
        #expect(!result.reached)
        #expect(result.reads.count == 8)
        #expect(result.last == reading(10))
    }

    @Test func halfOpenNeedsTwoAgreeingConsecutiveReads() throws {
        let script = Script([reading(0), reading(60), reading(100), reading(128), reading(130), reading(130.2)])
        let result = try PoseVerifier.verify(target: target("half-open"), read: script.next)
        #expect(result.reached)
        #expect(result.reads.count == 6)
        #expect(result.last == reading(130.2))
    }

    @Test func aDriftingHalfOpenIsNotStable() throws {
        let angles = [20, 40, 60, 80, 100, 120, 140, 160].map { reading(Double($0)) }
        let script = Script(angles)
        let result = try PoseVerifier.verify(target: target("half-open"), read: script.next)
        #expect(!result.reached)
        #expect(result.reads.count == 8)
    }

    @Test func halfOpenStabilityIgnoresAnInvalidNeighbour() throws {
        let script = Script([reading(130, valid: false), reading(130), reading(130.1)])
        let result = try PoseVerifier.verify(target: target("half-open"), read: script.next)
        #expect(result.reached)
        #expect(result.reads.count == 3)
    }

    @Test func aThrowingReadAborts() {
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try PoseVerifier.verify(target: FoldTarget.parse("open")!) { _ in throw Boom() }
        }
    }
}

@Suite struct PanelCheckTests {
    private func table(lit: String) -> [Display] {
        ["LCD", "LCD-1"].map {
            Display(
                name: $0,
                backlightState: $0 == lit ? "activeOn" : "off",
                primary: $0 == "LCD",
                integrated: true
            )
        }
    }

    /// A clock that only moves when the code under test sleeps.
    private final class FakeClock {
        var elapsed: TimeInterval = 0
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        func now() -> Date { start.addingTimeInterval(elapsed) }
        func sleep(_ seconds: TimeInterval) { elapsed += seconds }
    }

    @Test func matchesImmediately() throws {
        var sleeps: [TimeInterval] = []
        let result = try PanelCheck.waitFor(
            expected: .inner,
            displays: { table(lit: "LCD-1") },
            sleep: { sleeps.append($0) }
        )
        #expect(result.matched)
        #expect(sleeps.isEmpty)
    }

    @Test func waitsForALaggingPanelSwitch() throws {
        var tables = [table(lit: "LCD"), table(lit: "LCD"), table(lit: "LCD-1")]
        var sleeps: [TimeInterval] = []
        let result = try PanelCheck.waitFor(
            expected: .inner,
            displays: { tables.count > 1 ? tables.removeFirst() : tables[0] },
            sleep: { sleeps.append($0) }
        )
        #expect(result.matched)
        #expect(sleeps.count == 2)
    }

    @Test func reportsTheWrongPanelWhenTheDeadlinePasses() throws {
        let clock = FakeClock()
        let result = try PanelCheck.waitFor(
            expected: .outer,
            timeout: 2,
            now: clock.now,
            displays: { table(lit: "LCD-1") },
            sleep: clock.sleep
        )
        #expect(!result.matched)
        #expect(result.lit?.name == "LCD-1")
        #expect(result.expected.name == "LCD")
        #expect(clock.elapsed == 2)
    }

    @Test func defaultsToATwentySecondDeadline() throws {
        let clock = FakeClock()
        let result = try PanelCheck.waitFor(
            expected: .outer,
            now: clock.now,
            displays: { table(lit: "LCD-1") },
            sleep: clock.sleep
        )
        #expect(!result.matched)
        #expect(clock.elapsed == 20)
    }

    @Test func aLatePanelSwitchWithinTheDeadlineStillMatches() throws {
        let clock = FakeClock()
        let result = try PanelCheck.waitFor(
            expected: .inner,
            now: clock.now,
            displays: { clock.elapsed >= 12 ? table(lit: "LCD-1") : table(lit: "none") },
            sleep: clock.sleep
        )
        #expect(result.matched)
        #expect(clock.elapsed == 12)
    }
}

@Suite struct SetArgumentsTests {
    @Test func spawnsTheGuestSet() {
        #expect(
            Simctl.setArguments(udid: "U", guestPath: "/g", argument: "half-open")
                == ["simctl", "spawn", "U", "/g", "set", "half-open"]
        )
    }
}
