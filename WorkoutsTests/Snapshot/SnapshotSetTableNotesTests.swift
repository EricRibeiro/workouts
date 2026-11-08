import Foundation
import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The set table header's block note keeps its natural height. One column, as in a block header.
    @MainActor
    struct SetTableNotesSnapshots {
        @Test(arguments: SnapshotVariant.all)
        func note(variant: SnapshotVariant) {
            let column = VStack(alignment: .leading, spacing: 2) {
                SetTableNoteLine(text: "Pause on the chest.", identifier: "snapshot.note", onEdit: {})
            }
            .padding(.horizontal, 16)
            Snapshot.assert(column, named: "note", variant: variant)
        }
    }
}
