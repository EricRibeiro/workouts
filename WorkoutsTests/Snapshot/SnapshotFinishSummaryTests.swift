import Foundation
import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The finish summary sheet: the check, the ordinal, the five white stats (gold PR count) and the PR sections.
    @MainActor
    struct FinishSummarySnapshots {
        @Test(arguments: SnapshotVariant.all)
        func summary(variant: SnapshotVariant) {
            Snapshot.assert(
                FinishSummaryView(summary: .sample),
                named: "summary",
                variant: variant,
                engine: .hosted(height: 844)
            )
        }
    }
}
