import Foundation
import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The set table's rows: every kind, a checked row, placeholders, a duration row and the refused-check row; then the
    /// template and bodyweight variants and checked warm-up and duration rows. One line at the default size, two lines at
    /// accessibility sizes.
    @MainActor
    struct SetRowSnapshots {
        @Test(arguments: SnapshotVariant.all)
        func rows(variant: SnapshotVariant) {
            Snapshot.assert(
                SnapshotSetRowHost(rows: SetRowDemo.sampleRows),
                named: "rows",
                variant: variant,
                engine: .hostedFitting
            )
        }

        @Test(arguments: SnapshotVariant.all)
        func templateRows(variant: SnapshotVariant) {
            let rows = [
                SetRowModel(
                    id: UUID(),
                    number: 1,
                    weightText: "60",
                    repsText: "8",
                    showsPrevious: false,
                    showsCheck: false
                ),
                SetRowModel(
                    id: UUID(),
                    number: 2,
                    kind: .drop,
                    weightText: "50",
                    repsText: "12",
                    showsPrevious: false,
                    showsCheck: false
                ),
                SetRowModel(
                    id: UUID(),
                    number: 3,
                    repsText: "15",
                    showsWeight: false,
                    showsPrevious: false,
                    showsCheck: false
                ),
                SetRowModel(
                    id: UUID(),
                    number: 4,
                    repsText: "12",
                    showsWeight: false,
                    showsPrevious: true
                ),
                SetRowModel(
                    id: UUID(),
                    number: 5,
                    kind: .warmup,
                    previousText: "40 kg × 10",
                    weightText: "40",
                    repsText: "10",
                    isChecked: true
                ),
                SetRowModel(
                    id: UUID(),
                    number: 6,
                    previousText: "10 kg × 45 s",
                    weightText: "10",
                    repsText: "45",
                    isChecked: true,
                    measure: .duration
                ),
                SetRowModel(
                    id: UUID(),
                    number: 7,
                    previousText: "60 s",
                    repsText: "60",
                    isChecked: true,
                    measure: .duration,
                    showsWeight: false
                ),
            ]
            Snapshot.assert(
                SnapshotSetRowHost(rows: rows),
                named: "templateRows",
                variant: variant,
                engine: .hostedFitting
            )
        }
    }
}
