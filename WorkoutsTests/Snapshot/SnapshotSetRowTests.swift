import Foundation
import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The set table's rows: every kind, a checked row, placeholders and a duration row; one line at the default size,
    /// two lines at accessibility sizes.
    @MainActor
    struct SetRowSnapshots {
        @Test(arguments: SnapshotVariant.all)
        func rows(variant: SnapshotVariant) {
            let rows = Array(SetRowDemo.sampleRows.prefix(7))  // ids are random but never drawn
            Snapshot.assert(SnapshotSetRowHost(rows: rows), named: "rows", variant: variant, engine: .hostedFitting)
        }
    }
}
