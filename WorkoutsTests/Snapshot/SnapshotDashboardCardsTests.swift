import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The History dashboard cards (This Week, Recent PRs, Last Workout): one column at phone width, two at inner-display
    /// width, and the empty state of a new install.
    @MainActor
    struct DashboardCardsSnapshots {
        private static func entry(_ name: String, day: Int, minutes: Int, volume: Double) -> HistoryEntry {
            let start =
                DateComponents(calendar: SnapshotFixtures.calendar, year: 2026, month: 10, day: day, hour: 18).date
                ?? SnapshotFixtures.now
            return HistoryEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000D00\(String(format: "%02d", day))") ?? UUID(),
                name: name,
                startedAt: start,
                durationSeconds: minutes * 60,
                volume: volume,
                unit: .kg,
                prCount: 1,
                exerciseNames: []
            )
        }

        /// Newest first, as the History list passes them. The fixed `now` is Sunday 1 November, so three are this week.
        private static let entries = [
            entry("Pull Day", day: 31, minutes: 62, volume: 9_450),
            entry("Push Day", day: 29, minutes: 55, volume: 8_120.5),
            entry("Leg Day", day: 27, minutes: 71, volume: 14_300),
            entry("Upper Body", day: 20, minutes: 48, volume: 7_600),
        ]

        private static let recentPRs = [
            RecentPR(
                workoutID: UUID(uuidString: "00000000-0000-0000-0000-00000000A001") ?? UUID(),
                exerciseID: UUID(uuidString: "00000000-0000-0000-0000-00000000B001") ?? UUID(),
                exerciseName: "Bench Press",
                date: SnapshotFixtures.now,
                kind: .e1rm,
                text: "e1RM 120 kg",
                recordCount: 2
            ),
            RecentPR(
                workoutID: UUID(uuidString: "00000000-0000-0000-0000-00000000A002") ?? UUID(),
                exerciseID: UUID(uuidString: "00000000-0000-0000-0000-00000000B002") ?? UUID(),
                exerciseName: "Barbell Row",
                date: SnapshotFixtures.now,
                kind: .heaviest,
                text: "100 kg × 5",
                recordCount: 1
            ),
        ]

        private func cards(populated: Bool = true) -> some View {
            DashboardCards(
                entries: populated ? Self.entries : [],
                recentPRs: populated ? Self.recentPRs : [],
                goal: 4,
                weekActiveKcal: populated ? 1_240 : nil,
                weekAverageBpm: populated ? 118 : nil,
                openWorkout: { _ in },
                calendar: SnapshotFixtures.calendar,
                now: SnapshotFixtures.now
            )
            .padding(.horizontal, 16)
        }

        @Test(arguments: SnapshotVariant.all)
        func phone(variant: SnapshotVariant) {
            Snapshot.assert(cards(), named: "phone", variant: variant)
        }

        /// Two columns at inner-display width, default text size only (at accessibility sizes the column minimum scales up
        /// and the grid is one column again, which `phone` covers). The grid measures its width in a state update, which
        /// `ImageRenderer` lays out for but does not re-fit the height to, and a hosted window cannot be wider than the
        /// scene; so the height is pinned (the cards are about 350 pt tall).
        @Test(arguments: SnapshotVariant.all.filter { $0.dynamicTypeSize == .large })
        func wide(variant: SnapshotVariant) {
            Snapshot.assert(
                cards().environment(\.horizontalSizeClass, .regular).frame(height: 372, alignment: .top),
                named: "wide",
                variant: variant,
                width: 800
            )
        }

        @Test(arguments: SnapshotVariant.all)
        func empty(variant: SnapshotVariant) {
            Snapshot.assert(cards(populated: false), named: "empty", variant: variant)
        }
    }
}
