import Foundation
import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The set table header's notes (PLAN 7.8b): a long sticky band stops at three lines with an ellipsis, a short one and the
    /// block note keep their natural height. One column, as in a block header.
    @MainActor
    struct SetTableNotesSnapshots {
        private static let long =
            "Keep the shoulder blades pinned back and down through the whole set. Lower for a slow three count, pause on the "
            + "chest without bouncing, and drive up through the heels. Grip just outside shoulder width, elbows at about "
            + "forty five degrees. If the left wrist hurts, drop the weight and use straps; never grind a rep."

        @Test(arguments: SnapshotVariant.all)
        func longBandAndNote(variant: SnapshotVariant) {
            let column = VStack(alignment: .leading, spacing: 2) {
                SetTableStickyBand(text: Self.long, identifier: "snapshot.band", onEdit: {})
                SetTableStickyBand(text: "Elbows in.", identifier: "snapshot.band.short", onEdit: nil)
                SetTableNoteLine(text: "Pause on the chest.", identifier: "snapshot.note", onEdit: {})
            }
            .padding(.horizontal, 16)
            Snapshot.assert(column, named: "long-band", variant: variant)
        }
    }
}
