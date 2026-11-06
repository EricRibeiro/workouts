import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The finished-workout heart-rate chart on the gallery's sample data (an interleaved superset merged into one band):
    /// at phone width, and at inner-display width where the regular size class labels the bands.
    @MainActor
    struct HeartRateChartSnapshots {
        private static let zones = [
            HeartRateZoneTime(index: 1, upperBPM: 138, seconds: 1800),
            HeartRateZoneTime(index: 2, lowerBPM: 139, upperBPM: 150, seconds: 525),
            HeartRateZoneTime(index: 3, lowerBPM: 151, upperBPM: 162, seconds: 75),
        ]

        private func chart() -> some View {
            let sample = HeartRateChartDemo.sample
            return HeartRateChart(
                series: sample.series,
                timeline: sample.timeline,
                average: 118,
                maximum: 161,
                zones: Self.zones
            )
            // The top axis label overhangs the plot; the screen's card padding gives it room, so the snapshot does too.
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }

        @Test(arguments: SnapshotVariant.all)
        func superset(variant: SnapshotVariant) {
            Snapshot.assert(chart(), named: "superset", variant: variant)
        }

        /// Regular width, as on the open Duo's inner display (the size class is forced; `ImageRenderer` has no window).
        @Test(arguments: SnapshotVariant.all)
        func supersetWide(variant: SnapshotVariant) {
            Snapshot.assert(
                chart().environment(\.horizontalSizeClass, .regular),
                named: "superset-wide",
                variant: variant,
                width: 700
            )
        }
    }
}
