import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The History calendar sheet on a fixed past month (the grid outlines today, which would otherwise move the
    /// reference once the month came round).
    @MainActor
    struct CalendarSheetSnapshots {
        private static func entry(day: Int) -> HistoryEntry {
            let start =
                DateComponents(calendar: SnapshotFixtures.calendar, year: 2026, month: 9, day: day, hour: 18).date
                ?? SnapshotFixtures.now
            return HistoryEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000C00\(String(format: "%02d", day))") ?? UUID(),
                name: "Workout \(day)",
                startedAt: start,
                durationSeconds: 3_600,
                volume: 5_000,
                unit: .kg,
                prCount: 0,
                exerciseNames: []
            )
        }

        @Test(arguments: SnapshotVariant.all)
        func month(variant: SnapshotVariant) {
            let entries = [1, 3, 4, 8, 10, 15, 17, 22, 24, 29].map(Self.entry)
            let september = DateComponents(calendar: SnapshotFixtures.calendar, year: 2026, month: 9, day: 15).date
            Snapshot.assert(
                CalendarSheet(
                    entries: entries,
                    month: september ?? SnapshotFixtures.now,
                    calendar: SnapshotFixtures.calendar,
                    open: { _ in }
                ),
                named: "month",
                variant: variant,
                engine: .hosted(height: 720)
            )
        }
    }
}
