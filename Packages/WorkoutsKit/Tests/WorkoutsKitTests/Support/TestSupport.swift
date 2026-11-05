import Foundation
import SwiftData

@testable import WorkoutsKit

/// Fixtures shared by the kit tests, so a suite declares only what is specific to it.
enum TestSupport {
    /// A fixed instant (2027-01-15 08:00 UTC) for tests that need a stable "now" and do not care which day it is.
    static let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    /// A Gregorian calendar in America/Toronto, the zone the date-sensitive history tests are written in.
    static let torontoCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto") ?? .gmt
        return calendar
    }()
}

/// A fresh in-memory, CloudKit-free container with the full schema.
func makeTestContainer() throws -> ModelContainer {
    try ModelContainer.workouts(inMemory: true, cloudKit: false)
}

/// A fresh context on its own in-memory container.
func makeTestContext() throws -> ModelContext {
    ModelContext(try makeTestContainer())
}

/// A workout with no exercises. Finished after `minutes`, or still running when `minutes` is nil. Inserted when a
/// `context` is given.
@discardableResult
func makeWorkout(
    in context: ModelContext? = nil,
    name: String = "w",
    startedAt: Date = TestSupport.referenceDate,
    minutes: Int? = 50,
    avgHeartRate: Double? = nil,
    activeEnergyKcal: Double? = nil
) -> Workout {
    let workout = Workout(
        name: name,
        startedAt: startedAt,
        finishedAt: minutes.map { startedAt.addingTimeInterval(Double($0) * 60) }
    )
    workout.avgHeartRate = avgHeartRate
    workout.activeEnergyKcal = activeEnergyKcal
    context?.insert(workout)
    return workout
}
