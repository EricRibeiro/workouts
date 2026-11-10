import SwiftUI
import Testing

@testable import Workouts

extension SnapshotTests {
    /// The logging screen's arrangement at the open Duo's two inner-display sizes and with no pane. The size class is forced
    /// and the area pinned (`ImageRenderer` has no window and no division region), so this proves placement, not type:
    /// default variant only.
    @MainActor
    struct BenchArrangementSnapshots {
        private static let variant = SnapshotVariant.all[0]

        private func arrangement(axes: Axis.Set, width: CGFloat, height: CGFloat) -> some View {
            ArrangementView {
                Color.blue.overlay(Text("primary").foregroundStyle(.white))
            } secondary: {
                Color.orange.overlay(Text("secondary").foregroundStyle(.white))
            }
            .arrangementViewStyle(BenchArrangementStyle(axes: axes, showsRestCountdown: false))
            .environment(\.horizontalSizeClass, .regular)
            .frame(width: width, height: height)
        }

        @Test func openWide() {
            Snapshot.assert(
                arrangement(axes: [.horizontal, .vertical], width: 951, height: 669),
                named: "open-wide",
                variant: Self.variant,
                width: 951
            )
        }

        @Test func openTall() {
            Snapshot.assert(
                arrangement(axes: [.horizontal, .vertical], width: 669, height: 951),
                named: "open-tall",
                variant: Self.variant,
                width: 669
            )
        }

        @Test func single() {
            Snapshot.assert(
                arrangement(axes: [], width: 951, height: 669),
                named: "single",
                variant: Self.variant,
                width: 951
            )
        }
    }
}
