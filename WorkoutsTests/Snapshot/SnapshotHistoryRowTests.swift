import Foundation
import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// A History row with PRs (the gold trophy count at the trailing edge), and one with the Apple Fitness values line.
    @MainActor
    struct HistoryRowSnapshots {
        private static func entry(prCount: Int) -> HistoryEntry {
            HistoryEntry(
                id: UUID(),
                name: "Push Day",
                startedAt: SnapshotFixtures.now.addingTimeInterval(-2 * 86_400),
                durationSeconds: 4_320,
                volume: 15_421,
                unit: .kg,
                prCount: prCount,
                exerciseNames: ["Bench Press (Barbell)"]
            )
        }

        @Test(arguments: SnapshotVariant.all)
        func withRecords(variant: SnapshotVariant) {
            Snapshot.assert(
                HistoryRow(entry: Self.entry(prCount: 3)).padding(.horizontal, 16),
                named: "history-with-records",
                variant: variant
            )
        }

        @Test(arguments: SnapshotVariant.all)
        func withHealth(variant: SnapshotVariant) {
            Snapshot.assert(
                HistoryRow(entry: Self.entry(prCount: 2), activeKcal: 266, avgBpm: 128).padding(.horizontal, 16),
                named: "history-with-health",
                variant: variant
            )
        }
    }
}
