import Foundation
import SwiftData
import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The workout detail header with the Apple Health values joined in: date and weather, the stat grid (duration, volume,
    /// records, active calories, heart rate, effort).
    @MainActor
    struct WorkoutHeaderSnapshots {
        private static let health = HealthWorkoutSummary(
            healthWorkoutID: "snapshot",
            start: SnapshotFixtures.now,
            end: SnapshotFixtures.now.addingTimeInterval(3_000),
            activeEnergyKcal: 266,
            totalEnergyKcal: 331,
            avgHeartRate: 128,
            maxHeartRate: 161,
            effort: HealthEffort(score: 6, isEstimated: true),
            weatherTemperatureCelsius: 18,
            weatherHumidityPercent: 83
        )

        private func detail() throws -> WorkoutDetail {
            let environment = try SnapshotFixtures.requireEnvironment()
            let finished = try environment.container.mainContext.fetch(Workout.allFinished)
            let newest = try #require(finished.max { $0.startedAt < $1.startedAt })
            return try #require(
                WorkoutDetail.make(
                    id: newest.id,
                    from: finished,
                    weightType: { environment.store.exercise(id: $0)?.weightType },
                    options: RecordsOptions(formula: SettingsStore.e1rmFormulaDefault, displayUnit: .kg),
                    now: SnapshotFixtures.now,
                    calendar: SnapshotFixtures.calendar
                )
            )
        }

        @Test(arguments: SnapshotVariant.all)
        func withHealth(variant: SnapshotVariant) throws {
            Snapshot.assert(
                DetailHeader(detail: try detail(), health: Self.health).padding(.horizontal, 16),
                named: "with-health",
                variant: variant
            )
        }

        @Test(arguments: SnapshotVariant.all)
        func withoutHealth(variant: SnapshotVariant) throws {
            Snapshot.assert(
                DetailHeader(detail: try detail(), health: nil).padding(.horizontal, 16),
                named: "without-health",
                variant: variant
            )
        }
    }
}
