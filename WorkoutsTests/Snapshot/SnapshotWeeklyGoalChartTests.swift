import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The History tab's weekly chart: workouts per week (bars below and at the goal, an empty week, the goal line) and
    /// volume per week with its 4-week average line.
    @MainActor
    struct WeeklyGoalChartSnapshots {
        private static let counts: [WeekCount] = {
            let calendar = SnapshotFixtures.calendar
            let monday = DateComponents(calendar: calendar, year: 2026, month: 11, day: 2).date ?? SnapshotFixtures.now
            return [2, 3, 4, 0, 1, 3, 5, 2].enumerated().map { index, count in
                WeekCount(
                    weekStart: calendar.date(byAdding: .weekOfYear, value: index - 7, to: monday) ?? monday,
                    count: count
                )
            }
        }()

        private static let volume: [WeekTotal] = zip(
            counts.map(\.weekStart),
            [14_200, 18_650, 22_318, 0, 9_400, 19_800, 25_100, 12_300]
        ).map { WeekTotal(weekStart: $0, workouts: 1, durationSeconds: 3600, volume: $1) }

        private static let averages: [Double?] = [nil, nil, nil, 18_900, 17_300, 12_900, 12_900, 13_650]

        @Test(arguments: SnapshotVariant.all)
        func weeks(variant: SnapshotVariant) {
            Snapshot.assert(
                WeeklyGoalChart(
                    mode: .constant(.workouts),
                    counts: Self.counts,
                    goal: 3,
                    calendar: SnapshotFixtures.calendar
                )
                .padding(.horizontal, 16),
                named: "weeks",
                variant: variant,
                engine: .hostedFitting
            )
        }

        @Test(arguments: SnapshotVariant.all)
        func volumeWeeks(variant: SnapshotVariant) {
            Snapshot.assert(
                WeeklyGoalChart(
                    mode: .constant(.volume),
                    counts: Self.counts,
                    goal: 3,
                    volume: Self.volume,
                    averages: Self.averages,
                    unit: .lb,
                    calendar: SnapshotFixtures.calendar
                )
                .padding(.horizontal, 16),
                named: "volume",
                variant: variant,
                engine: .hostedFitting
            )
        }
    }
}
