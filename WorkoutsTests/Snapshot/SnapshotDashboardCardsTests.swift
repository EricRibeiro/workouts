import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The History dashboard as it ships: the compact page (hero, then Recent PRs and Last Workout) at phone width, the
    /// regular two-column `DashboardColumns` at inner-display width, and the empty and loading states of a new install.
    @MainActor
    struct DashboardCardsSnapshots {
        private static func entry(
            _ name: String,
            month: Int = 10,
            day: Int,
            minutes: Int,
            volume: Double
        ) -> HistoryEntry {
            let start =
                DateComponents(calendar: SnapshotFixtures.calendar, year: 2026, month: month, day: day, hour: 18).date
                ?? SnapshotFixtures.now
            return HistoryEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000D0" + String(format: "%02d%02d", month, day))
                    ?? UUID(),
                name: name,
                startedAt: start,
                durationSeconds: minutes * 60,
                volume: volume,
                unit: .kg,
                prCount: 1,
                exerciseNames: []
            )
        }

        /// Newest first, as the History list passes them. The fixed `now` is Sunday 1 November, so three are this week and the
        /// older ones fill the four weeks before it (the "usually" lines).
        private static let entries = [
            entry("Pull Day", day: 31, minutes: 62, volume: 9_450),
            entry("Push Day", day: 29, minutes: 55, volume: 8_120.5),
            entry("Leg Day", day: 27, minutes: 71, volume: 14_300),
            entry("Upper Body", day: 20, minutes: 48, volume: 7_600),
            entry("Push Day", day: 13, minutes: 52, volume: 8_900),
            entry("Pull Day", day: 6, minutes: 60, volume: 10_200),
            entry("Leg Day", month: 9, day: 30, minutes: 66, volume: 12_800),
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
            pr("00000000-0000-0000-0000-00000000A003", "Overhead Press", .heaviest, "60 kg × 5"),
            pr("00000000-0000-0000-0000-00000000A004", "Deadlift", .e1rm, "e1RM 180 kg"),
            pr("00000000-0000-0000-0000-00000000A005", "Pull-Up", .repsAtWeight, "BW × 12"),
        ]

        private static func pr(_ id: String, _ name: String, _ kind: RecordKind, _ text: String) -> RecentPR {
            RecentPR(
                workoutID: UUID(uuidString: id) ?? UUID(),
                exerciseID: UUID(),
                exerciseName: name,
                date: SnapshotFixtures.now,
                kind: kind,
                text: text,
                recordCount: 1
            )
        }

        /// The compact History page: the hero, then the rest (the weekly chart between them has its own snapshots).
        private func compact(populated: Bool = true, loaded: Bool = true) -> some View {
            func part(_ part: DashboardCards.Part) -> DashboardCards {
                DashboardCards(
                    entries: populated ? Self.entries : [],
                    recentPRs: populated ? Self.recentPRs : [],
                    goal: 4,
                    weekActiveKcal: populated ? 1_240 : nil,
                    weekAverageBpm: populated ? 118 : nil,
                    isLoaded: loaded,
                    part: part,
                    openWorkout: { _ in },
                    calendar: SnapshotFixtures.calendar,
                    now: SnapshotFixtures.now
                )
            }
            return VStack(spacing: Metrics.dashboardSpacing) {
                part(.hero)
                part(.rest)
            }
            .padding(.horizontal, 16)
        }

        @Test(arguments: SnapshotVariant.all)
        func phone(variant: SnapshotVariant) {
            Snapshot.assert(compact(), named: "phone", variant: variant, engine: .hostedFitting)
        }

        /// The regular layout: hero over the chart on the left, Recent PRs (five rows) over Last Workout on the right, every
        /// card at its natural height. The chart is a stand-in of fixed height (`WeeklyGoalSection` reads the clock; the
        /// chart has its own snapshots). Default text size only: at accessibility sizes the layout is the compact page's.
        @Test(arguments: SnapshotVariant.all.filter { $0.dynamicTypeSize == .large })
        func wide(variant: SnapshotVariant) {
            let columns = DashboardColumns(
                entries: Self.entries,
                recentPRs: Self.recentPRs,
                weekActiveKcal: 1_240,
                weekAverageBpm: 118,
                calendar: SnapshotFixtures.calendar,
                now: SnapshotFixtures.now,
                chart: {
                    Text("Weekly chart")
                        .foregroundStyle(.secondary)
                        .frame(height: 220)
                        .dashboardCardStyle()
                },
                openWorkout: { _ in }
            )
            Snapshot.assert(
                columns.padding(.horizontal, 16),
                named: "wide",
                variant: variant,
                width: 800
            )
        }

        @Test(arguments: SnapshotVariant.all)
        func empty(variant: SnapshotVariant) {
            Snapshot.assert(compact(populated: false), named: "empty", variant: variant, engine: .hostedFitting)
        }

        /// The first frame, before the history summary lands: This Week and Recent PRs are placeholder blocks, not "0 / 4"
        /// and "No records yet".
        @Test(arguments: SnapshotVariant.all)
        func loading(variant: SnapshotVariant) {
            Snapshot.assert(
                compact(populated: false, loaded: false),
                named: "dashboardLoading",
                variant: variant,
                engine: .hostedFitting
            )
        }
    }
}
