import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The History tab's workouts-per-week chart: bars below and at the goal, an empty week, the goal line.
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

        @Test(arguments: SnapshotVariant.all)
        func weeks(variant: SnapshotVariant) {
            Snapshot.assert(
                WeeklyGoalChart(counts: Self.counts, goal: 3, calendar: SnapshotFixtures.calendar)
                    .padding(.horizontal, 16),
                named: "weeks",
                variant: variant
            )
        }
    }
}
