import Foundation

extension Workout {
    /// The matched Fitness workout, rebuilt from the stored fields; nil unless `healthWorkoutID` is set. Start and end
    /// are this workout's own (the matcher pairs them by overlap, and the details screen only shows the duration of ours).
    /// A series that fails to decode reads as empty.
    public var healthSummary: HealthWorkoutSummary? {
        guard let healthWorkoutID else { return nil }
        let series = heartRateSeriesData.flatMap { try? JSONDecoder().decode([HeartRatePoint].self, from: $0) } ?? []
        return HealthWorkoutSummary(
            healthWorkoutID: healthWorkoutID,
            start: startedAt,
            end: finishedAt ?? startedAt,
            activeEnergyKcal: activeEnergyKcal,
            totalEnergyKcal: totalEnergyKcal,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            heartRateSeries: series
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
        heartRateSeriesData = summary.heartRateSeries.isEmpty ? nil : try? JSONEncoder().encode(summary.heartRateSeries)
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

    /// The stored series, for export (nil when none).
    var heartRateSeries: [HeartRatePoint]? {
        heartRateSeriesData.flatMap { try? JSONDecoder().decode([HeartRatePoint].self, from: $0) }
    }
}
