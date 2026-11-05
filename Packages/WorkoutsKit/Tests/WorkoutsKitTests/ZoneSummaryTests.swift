import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct ZoneSummaryTests {
    private static func zones(_ seconds: [TimeInterval], upper1: Double? = 139) -> [HeartRateZoneTime] {
        seconds.enumerated().map { index, secs in
            HeartRateZoneTime(index: index + 1, upperBPM: index == 0 ? upper1 : nil, seconds: secs)
        }
    }

    @Test func allZoneOneIsNotMeaningful() {
        let summary = ZoneSummary(zones: Self.zones([2400, 0, 0, 0, 0]))
        #expect(!summary.isMeaningful)
        #expect(summary.caption == "Zone 1 the whole time \u{00B7} up to 139 bpm")
        #expect(summary.zonesWithTime.map(\.index) == [1])
    }

    @Test func tenPercentOutsideZoneOneIsMeaningful() {
        // 10 % of 1000 s, under 120 s.
        #expect(ZoneSummary(zones: Self.zones([900, 100])).isMeaningful)
        #expect(!ZoneSummary(zones: Self.zones([920, 80])).isMeaningful)
    }

    @Test func twoMinutesOutsideZoneOneIsMeaningful() {
        // 120 s of 7200 s is under 10 %, but reaches the absolute threshold.
        #expect(ZoneSummary(zones: Self.zones([7080, 120])).isMeaningful)
        #expect(!ZoneSummary(zones: Self.zones([7090, 110])).isMeaningful)
    }

    @Test func zonesWithTimeSkipsEmptyZones() {
        let summary = ZoneSummary(zones: Self.zones([600, 525, 0, 90, 0]))
        #expect(summary.zonesWithTime.map(\.index) == [1, 2, 4])
        #expect(ZoneSummary.legendText(summary.zonesWithTime[1]) == "Zone 2 \u{00B7} 8:45")
    }

    @Test func emptyAndZeroTimeHaveNothing() {
        for zones in [[], Self.zones([0, 0, 0])] {
            let summary = ZoneSummary(zones: zones)
            #expect(!summary.isMeaningful)
            #expect(summary.caption == nil)
            #expect(summary.zonesWithTime.isEmpty)
        }
    }

    @Test func captionOmitsMissingUpperBound() {
        #expect(ZoneSummary(zones: Self.zones([600], upper1: nil)).caption == "Zone 1 the whole time")
    }

    @Test func zeroBasedSnapshotsAreRepaired() {
        let summary = ZoneSummary(zones: [
            HeartRateZoneTime(index: 0, upperBPM: 120, seconds: 100),
            HeartRateZoneTime(index: 1, seconds: 500),
        ])
        #expect(summary.zones.map(\.index) == [1, 2])
        #expect(summary.isMeaningful)
    }
}
