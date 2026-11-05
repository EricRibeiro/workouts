import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct WorkoutHealthFieldsTests {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static let hour: TimeInterval = 3600

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer.workouts(inMemory: true, cloudKit: false))
    }

    private static func summary(id: String = "HK-1") -> HealthWorkoutSummary {
        HealthWorkoutSummary(
            healthWorkoutID: id,
            start: t0,
            end: t0.addingTimeInterval(3000),
            activeEnergyKcal: 312.5,
            totalEnergyKcal: 380,
            avgHeartRate: 118.4,
            maxHeartRate: 171,
            heartRateSeries: [
                HeartRatePoint(offset: 0, bpm: 90),
                HeartRatePoint(offset: 60, bpm: 125.5),
                HeartRatePoint(offset: 120, bpm: 171),
            ]
        )
    }

    private static func finished(at finish: Date = t0.addingTimeInterval(3000)) -> Workout {
        Workout(name: "Push", startedAt: t0, finishedAt: finish, updatedAt: t0)
    }

    // MARK: apply -> summary

    @Test func applyRoundTripsThroughTheStoreWithTheSeries() throws {
        let context = try makeContext()
        let workout = Self.finished()
        context.insert(workout)
        #expect(workout.healthSummary == nil)

        workout.applyHealth(Self.summary(), checkedAt: Self.t0.addingTimeInterval(4000))
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(fetched.healthWorkoutID == "HK-1")
        #expect(fetched.healthCheckedAt == Self.t0.addingTimeInterval(4000))
        // Start and end come from the workout itself.
        #expect(fetched.healthSummary == Self.summary())
    }

    @Test func clearHealthRemovesEverythingButLeavesUpdatedAt() throws {
        let workout = Self.finished()
        workout.applyHealth(Self.summary(), checkedAt: Self.t0.addingTimeInterval(4000))
        workout.clearHealth()
        #expect(workout.healthSummary == nil)
        #expect(workout.healthWorkoutID == nil && workout.healthCheckedAt == nil)
        #expect(workout.activeEnergyKcal == nil && workout.totalEnergyKcal == nil)
        #expect(workout.avgHeartRate == nil && workout.maxHeartRate == nil && workout.heartRateSeriesData == nil)
        #expect(workout.updatedAt == Self.t0)
        // Cleared means "never looked up": the next pass picks it up again.
        #expect(workout.needsHealthCheck(now: Self.t0.addingTimeInterval(4100)))
    }

    @Test func badSeriesDataReadsAsEmpty() {
        let workout = Self.finished()
        workout.applyHealth(Self.summary(), checkedAt: Self.t0)
        workout.heartRateSeriesData = Data("not json".utf8)
        #expect(workout.healthSummary?.heartRateSeries == [])
        #expect(workout.healthSummary?.avgHeartRate == 118.4)
    }

    @Test func emptySeriesStoresNothing() {
        let workout = Self.finished()
        var summary = Self.summary()
        summary.heartRateSeries = []
        workout.applyHealth(summary, checkedAt: Self.t0)
        #expect(workout.heartRateSeriesData == nil)
        #expect(workout.healthSummary?.heartRateSeries == [])
    }

    @Test func nilSummaryOnlyStampsTheCheckTime() {
        let workout = Self.finished()
        workout.applyHealth(nil, checkedAt: Self.t0)
        #expect(workout.healthCheckedAt == Self.t0)
        #expect(workout.healthWorkoutID == nil && workout.activeEnergyKcal == nil && workout.heartRateSeriesData == nil)

        // A later empty lookup does not wipe an existing match.
        workout.applyHealth(Self.summary(), checkedAt: Self.t0.addingTimeInterval(10))
        workout.applyHealth(nil, checkedAt: Self.t0.addingTimeInterval(20))
        #expect(workout.healthCheckedAt == Self.t0.addingTimeInterval(20))
        #expect(workout.healthSummary == Self.summary())
    }

    @Test func applyLeavesUpdatedAtAlone() {
        let workout = Self.finished()
        workout.applyHealth(Self.summary(), checkedAt: Self.t0.addingTimeInterval(9999))
        workout.applyHealth(nil, checkedAt: Self.t0.addingTimeInterval(99999))
        #expect(workout.updatedAt == Self.t0)
    }

    // MARK: needsHealthCheck

    @Test func needsHealthCheckTable() {
        let finish = Self.t0
        let h = Self.hour

        func workout(
            finished: Bool = true,
            matched: Bool = false,
            checkedAgo: TimeInterval? = nil,
            now: Date
        ) -> Workout {
            let w = Workout(startedAt: finish.addingTimeInterval(-3000), finishedAt: finished ? finish : nil)
            if matched { w.healthWorkoutID = "HK-1" }
            if let checkedAgo { w.healthCheckedAt = now.addingTimeInterval(-checkedAgo) }
            return w
        }

        let soon = finish.addingTimeInterval(h)
        let later = finish.addingTimeInterval(2 * 86400)
        let old = finish.addingTimeInterval(8 * 86400)

        #expect(workout(finished: false, now: soon).needsHealthCheck(now: soon) == false)
        #expect(workout(matched: true, now: soon).needsHealthCheck(now: soon) == false)
        #expect(workout(now: soon).needsHealthCheck(now: soon))  // never checked
        #expect(workout(checkedAgo: 3 * h, now: soon).needsHealthCheck(now: soon) == false)  // checked recently
        #expect(workout(checkedAgo: 7 * h, now: later).needsHealthCheck(now: later))  // checked long ago
        #expect(workout(checkedAgo: 7 * h, now: old).needsHealthCheck(now: old) == false)  // too old
        #expect(workout(now: old).needsHealthCheck(now: old) == false)  // too old, never checked

        // Custom windows.
        let w = workout(checkedAgo: 2 * h, now: soon)
        #expect(w.needsHealthCheck(now: soon, recheckAfter: h))
        #expect(w.needsHealthCheck(now: soon, recheckAfter: h, giveUpAfter: 30 * 60) == false)
    }

    // MARK: Export and import

    private func exportedDocument(from workout: Workout) throws -> WorkoutsJSON {
        let context = try makeContext()
        context.insert(workout)
        try context.save()
        return try Exporter.document(from: context)
    }

    @Test func healthFieldsRoundTripThroughExportAndImport() throws {
        let workout = Self.finished()
        workout.applyHealth(Self.summary(), checkedAt: Self.t0.addingTimeInterval(4000))
        let document = try exportedDocument(from: workout)

        let dto = try #require(document.workouts.first)
        #expect(dto.healthWorkoutId == "HK-1")
        #expect(dto.heartRateSeries?.count == 3)

        // Through the JSON text too.
        let decoded = try WorkoutsJSON.decode(try document.encoded())
        let target = try makeContext()
        _ = try Importer.apply(decoded, to: target)
        let imported = try #require(try target.fetch(FetchDescriptor<Workout>()).first)
        #expect(imported.healthSummary == Self.summary())
        #expect(imported.healthCheckedAt == Self.t0.addingTimeInterval(4000))
        #expect(imported.avgHeartRate == 118.4 && imported.totalEnergyKcal == 380)
    }

    @Test func oldDocumentWithoutHealthFieldsStillImportsAndKeepsLocalHealth() throws {
        let workout = Self.finished()
        let json = try exportedDocument(from: workout).encoded()
        let text = try #require(String(data: json, encoding: .utf8))
        // A file from before the fields existed has none of these keys.
        for key in ["healthWorkoutId", "heartRateSeries", "healthCheckedAt", "avgHeartRate"] {
            #expect(!text.contains("\"\(key)\""))
        }
        let old = try WorkoutsJSON.decode(Data(text.utf8))
        #expect(old.workouts.first?.healthWorkoutId == nil)

        // Into an empty store: nil fields.
        let empty = try makeContext()
        _ = try Importer.apply(old, to: empty)
        let fresh = try #require(try empty.fetch(FetchDescriptor<Workout>()).first)
        #expect(fresh.healthSummary == nil && fresh.healthCheckedAt == nil)

        // Over a store that has Fitness data: a newer old-format row does not clear it.
        let store = try makeContext()
        let local = Self.finished()
        local.id = try #require(old.workouts.first?.id)
        local.applyHealth(Self.summary(), checkedAt: Self.t0)
        store.insert(local)
        var newer = old
        newer.workouts[0].updatedAt = Self.t0.addingTimeInterval(500)
        _ = try Importer.apply(newer, to: store)
        let kept = try #require(try store.fetch(FetchDescriptor<Workout>()).first)
        #expect(kept.updatedAt == Self.t0.addingTimeInterval(500))
        #expect(kept.healthSummary == Self.summary())
    }

    // MARK: More Fitness details (PLAN 7.1b e4)

    private static func richSummary() -> HealthWorkoutSummary {
        var summary = Self.summary()
        summary.effort = HealthEffort(score: 7.5, isEstimated: true)
        summary.zones = [
            HeartRateZoneTime(index: 1, lowerBPM: nil, upperBPM: 110, seconds: 600),
            HeartRateZoneTime(index: 2, lowerBPM: 110, upperBPM: 140, seconds: 1500),
            HeartRateZoneTime(index: 3, lowerBPM: 140, upperBPM: nil, seconds: 900),
        ]
        summary.weatherTemperatureCelsius = 21.5
        summary.weatherHumidityPercent = 63
        summary.timeZoneIdentifier = "Europe/Lisbon"
        summary.details = HealthWorkoutDetails(
            statistics: [
                "HKQuantityTypeIdentifierActiveEnergyBurned": HealthStatistic(sum: 312.5, unit: "kcal"),
                "HKQuantityTypeIdentifierHeartRate": HealthStatistic(
                    average: 118.4,
                    minimum: 88,
                    maximum: 171,
                    mostRecent: 95,
                    unit: "count/min"
                ),
            ],
            metadata: ["HKWeatherCondition": "clear", "HKIndoorWorkout": "true"],
            events: [
                HealthInterval(
                    type: "pause",
                    start: Self.t0.addingTimeInterval(600),
                    end: Self.t0.addingTimeInterval(660)
                )
            ],
            activities: [HealthInterval(type: "strength", start: Self.t0, end: Self.t0.addingTimeInterval(3000))],
            sourceName: "Eric's Apple Watch",
            sourceBundleID: "com.apple.health.ABC",
            deviceName: "Apple Watch",
            deviceModel: "Watch7,1",
            deviceHardwareVersion: "Watch7,1",
            deviceSoftwareVersion: "27.2",
            route: [
                HealthRoutePoint(latitude: 38.72, longitude: -9.14, altitude: 12, timestamp: Self.t0),
                HealthRoutePoint(latitude: 38.73, longitude: -9.15, timestamp: Self.t0.addingTimeInterval(30)),
            ]
        )
        return summary
    }

    @Test func storedZeroBasedZonesReadAsOneBased() throws {
        let workout = Self.finished()
        var summary = Self.richSummary()
        summary.zones = summary.zones.map { zone in
            var zone = zone
            zone.index -= 1
            return zone
        }
        workout.applyHealth(summary, checkedAt: Self.t0)
        #expect(workout.healthSummary?.zones.map(\.index) == [1, 2, 3])
    }

    @Test func detailsRoundTripThroughApplyAndTheStore() throws {
        let context = try makeContext()
        let workout = Self.finished()
        context.insert(workout)
        workout.applyHealth(Self.richSummary(), checkedAt: Self.t0)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(fetched.effortScore == 7.5 && fetched.effortIsEstimated == true)
        #expect(fetched.weatherTemperatureCelsius == 21.5 && fetched.weatherHumidityPercent == 63)
        #expect(fetched.healthTimeZone == "Europe/Lisbon")
        #expect(fetched.heartRateZonesData != nil && fetched.healthDetailsData != nil)
        #expect(fetched.healthSummary == Self.richSummary())
    }

    @Test func summaryWithoutNewFieldsLeavesThemNil() {
        let workout = Self.finished()
        workout.applyHealth(Self.summary(), checkedAt: Self.t0)
        #expect(workout.effortScore == nil && workout.effortIsEstimated == nil)
        #expect(workout.heartRateZonesData == nil && workout.healthDetailsData == nil)
        #expect(workout.healthSummary?.effort == nil && workout.healthSummary?.zones == [])
        #expect(workout.healthSummary?.details == nil)
    }

    @Test func clearHealthClearsTheNewFields() {
        let workout = Self.finished()
        workout.applyHealth(Self.richSummary(), checkedAt: Self.t0)
        workout.clearHealth()
        #expect(workout.effortScore == nil && workout.effortIsEstimated == nil)
        #expect(workout.heartRateZonesData == nil && workout.healthDetailsData == nil)
        #expect(workout.weatherTemperatureCelsius == nil && workout.weatherHumidityPercent == nil)
        #expect(workout.healthTimeZone == nil)
        #expect(workout.healthSummary == nil)
    }

    @Test func badZonesAndDetailsDataReadAsEmptyAndNil() {
        let workout = Self.finished()
        workout.applyHealth(Self.richSummary(), checkedAt: Self.t0)
        workout.heartRateZonesData = Data("nope".utf8)
        workout.healthDetailsData = Data("nope".utf8)
        let summary = workout.healthSummary
        #expect(summary?.zones == [])
        #expect(summary?.details == nil)
        #expect(summary?.effort == HealthEffort(score: 7.5, isEstimated: true))
        #expect(workout.heartRateZones == nil && workout.healthDetails == nil)
    }

    @Test func effortWithoutEstimatedFlagReadsAsRated() {
        let workout = Self.finished()
        workout.applyHealth(Self.summary(), checkedAt: Self.t0)
        workout.effortScore = 6
        #expect(workout.healthSummary?.effort == HealthEffort(score: 6, isEstimated: false))
    }

    @Test func detailsBlobWithUnknownKeysAndMissingKeysStillDecodes() throws {
        let json = """
            {"version": 2, "futureThing": {"a": 1}, "sourceName": "Watch",
             "statistics": {"X": {"sum": 1, "unit": "kcal", "newStat": 5}},
             "events": [{"type": "pause", "start": 0, "end": 1, "extra": true}]}
            """
        let details = try JSONDecoder().decode(HealthWorkoutDetails.self, from: Data(json.utf8))
        #expect(details.version == 2)
        #expect(details.sourceName == "Watch")
        #expect(details.statistics["X"]?.sum == 1 && details.statistics["X"]?.average == nil)
        #expect(details.events.count == 1)
        #expect(details.metadata.isEmpty && details.activities.isEmpty && details.route.isEmpty)

        // An empty object is a valid (version 1) snapshot.
        let empty = try JSONDecoder().decode(HealthWorkoutDetails.self, from: Data("{}".utf8))
        #expect(empty == HealthWorkoutDetails())

        // And it survives being stored on a workout.
        let workout = Self.finished()
        workout.applyHealth(Self.summary(), checkedAt: Self.t0)
        workout.healthDetailsData = Data(json.utf8)
        #expect(workout.healthSummary?.details?.version == 2)
    }

    @Test func detailsRoundTripThroughExportAndImport() throws {
        let workout = Self.finished()
        workout.applyHealth(Self.richSummary(), checkedAt: Self.t0.addingTimeInterval(4000))
        let document = try exportedDocument(from: workout)

        let dto = try #require(document.workouts.first)
        #expect(dto.effortScore == 7.5 && dto.effortIsEstimated == true)
        #expect(dto.heartRateZones?.count == 3)
        #expect(dto.healthTimeZone == "Europe/Lisbon")
        #expect(dto.healthDetails?.statistics.count == 2)

        let decoded = try WorkoutsJSON.decode(try document.encoded())
        let target = try makeContext()
        _ = try Importer.apply(decoded, to: target)
        let imported = try #require(try target.fetch(FetchDescriptor<Workout>()).first)
        #expect(imported.healthSummary == Self.richSummary())
    }

    @Test func oldDocumentDoesNotClearStoredDetails() throws {
        let workout = Self.finished()
        let json = try exportedDocument(from: workout).encoded()
        let text = try #require(String(data: json, encoding: .utf8))
        for key in [
            "effortScore", "effortIsEstimated", "heartRateZones", "weatherTemperatureCelsius",
            "weatherHumidityPercent", "healthTimeZone", "healthDetails",
        ] {
            #expect(!text.contains("\"\(key)\""))
        }
        let old = try WorkoutsJSON.decode(Data(text.utf8))

        let store = try makeContext()
        let local = Self.finished()
        local.id = try #require(old.workouts.first?.id)
        local.applyHealth(Self.richSummary(), checkedAt: Self.t0)
        store.insert(local)
        var newer = old
        newer.workouts[0].updatedAt = Self.t0.addingTimeInterval(500)
        _ = try Importer.apply(newer, to: store)
        let kept = try #require(try store.fetch(FetchDescriptor<Workout>()).first)
        #expect(kept.updatedAt == Self.t0.addingTimeInterval(500))
        #expect(kept.healthSummary == Self.richSummary())
    }
}
