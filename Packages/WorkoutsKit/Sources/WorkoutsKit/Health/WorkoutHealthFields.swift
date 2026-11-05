import Foundation
import os

nonisolated enum HealthBlob {
    /// Decodes a stored blob; a failure is logged and reads as no data.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data?, field: String) -> T? {
        guard let data else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            KitLog.health.error(
                "Could not decode stored \(field, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Encodes a value for storage; a failure is logged and nothing is stored.
    static func encode<T: Encodable>(_ value: T, field: String) -> Data? {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            KitLog.health.error(
                "Could not encode \(field, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}

extension Workout {
    /// The matched Fitness workout, rebuilt from the stored fields; nil unless `healthWorkoutID` is set. Start and end
    /// are this workout's own (the matcher pairs them by overlap, and the details screen only shows the duration of ours).
    /// A series that fails to decode reads as empty (and is logged).
    public var healthSummary: HealthWorkoutSummary? {
        guard let healthWorkoutID else { return nil }
        let zones = HeartRateZoneTime.oneBased(heartRateZones ?? [])
        let series = HealthBlob.decode([HeartRatePoint].self, from: heartRateSeriesData, field: "heartRateSeries") ?? []
        return HealthWorkoutSummary(
            healthWorkoutID: healthWorkoutID,
            start: startedAt,
            end: finishedAt ?? startedAt,
            activeEnergyKcal: activeEnergyKcal,
            totalEnergyKcal: totalEnergyKcal,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            heartRateSeries: series,
            effort: effortScore.map { HealthEffort(score: $0, isEstimated: effortIsEstimated ?? false) },
            zones: zones,
            weatherTemperatureCelsius: weatherTemperatureCelsius,
            weatherHumidityPercent: weatherHumidityPercent,
            timeZoneIdentifier: healthTimeZone,
            details: healthDetails
        )
    }

    /// Stores the Fitness details and stamps `healthCheckedAt`. With `nil` (no match found) only the stamp changes, so
    /// a match already stored is never lost to a later empty lookup. Does **not** touch `updatedAt`: Fitness data is not
    /// a user edit, and `updatedAt` drives the import's last-write-wins and the history/exercise caches' fingerprints.
    public func applyHealth(_ summary: HealthWorkoutSummary?, checkedAt: Date) {
        healthCheckedAt = checkedAt
        guard let summary else { return }
        healthWorkoutID = summary.healthWorkoutID
        activeEnergyKcal = summary.activeEnergyKcal
        totalEnergyKcal = summary.totalEnergyKcal
        avgHeartRate = summary.avgHeartRate
        maxHeartRate = summary.maxHeartRate
        heartRateSeriesData =
            summary.heartRateSeries.isEmpty
            ? nil : HealthBlob.encode(summary.heartRateSeries, field: "heartRateSeries")
        effortScore = summary.effort?.score
        effortIsEstimated = summary.effort?.isEstimated
        heartRateZonesData = summary.zones.isEmpty ? nil : HealthBlob.encode(summary.zones, field: "heartRateZones")
        weatherTemperatureCelsius = summary.weatherTemperatureCelsius
        weatherHumidityPercent = summary.weatherHumidityPercent
        healthTimeZone = summary.timeZoneIdentifier
        healthDetailsData = summary.details.flatMap { HealthBlob.encode($0, field: "healthDetails") }
    }

    /// Removes everything Fitness added: the matched workout, its numbers and series, and the lookup stamp, so a later
    /// opt-in looks the workout up afresh. Like `applyHealth`, leaves `updatedAt` alone.
    public func clearHealth() {
        healthWorkoutID = nil
        healthCheckedAt = nil
        activeEnergyKcal = nil
        totalEnergyKcal = nil
        avgHeartRate = nil
        maxHeartRate = nil
        heartRateSeriesData = nil
        effortScore = nil
        effortIsEstimated = nil
        heartRateZonesData = nil
        weatherTemperatureCelsius = nil
        weatherHumidityPercent = nil
        healthTimeZone = nil
        healthDetailsData = nil
    }

    /// True when the app should look for a Fitness match: the workout is finished, not matched yet, was never checked or
    /// last checked more than `recheckAfter` ago, and finished less than `giveUpAfter` ago (Fitness data for older
    /// workouts is not worth chasing).
    public func needsHealthCheck(
        now: Date,
        recheckAfter: TimeInterval = 6 * 3600,
        giveUpAfter: TimeInterval = 7 * 86400
    ) -> Bool {
        guard let finishedAt, healthWorkoutID == nil else { return false }
        guard now.timeIntervalSince(finishedAt) < giveUpAfter else { return false }
        guard let healthCheckedAt else { return true }
        return now.timeIntervalSince(healthCheckedAt) > recheckAfter
    }

    /// The stored zones, for export (nil when none or unreadable).
    var heartRateZones: [HeartRateZoneTime]? {
        HealthBlob.decode([HeartRateZoneTime].self, from: heartRateZonesData, field: "heartRateZones")
    }

    /// The stored details snapshot, for export (nil when none or unreadable).
    var healthDetails: HealthWorkoutDetails? {
        HealthBlob.decode(HealthWorkoutDetails.self, from: healthDetailsData, field: "healthDetails")
    }

    /// The stored series, for export (nil when none).
    var heartRateSeries: [HeartRatePoint]? {
        HealthBlob.decode([HeartRatePoint].self, from: heartRateSeriesData, field: "heartRateSeries")
    }
}
