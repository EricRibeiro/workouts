import Foundation

/// Finds and reads the Fitness workout that matches one of ours.
public nonisolated struct HealthEnrichment: Sendable {
    public var source: any HealthSource
    public var matcher: HealthMatcher
    /// Upper bound for the stored heart-rate series.
    public var maxSeriesPoints: Int

    public init(
        source: any HealthSource,
        matcher: HealthMatcher = HealthMatcher(),
        maxSeriesPoints: Int = 60
    ) {
        self.source = source
        self.matcher = matcher
        self.maxSeriesPoints = maxSeriesPoints
    }

    /// Queries the slack-widened window, matches, and returns the matched workout's summary with its series downsampled.
    /// Nil when nothing matches. Source errors (`HealthSourceError`) propagate.
    public func enrich(
        workoutStart: Date,
        workoutEnd: Date,
        claimed: Set<String> = []
    ) async throws -> HealthWorkoutSummary? {
        let window = matcher.window(start: workoutStart, end: workoutEnd)
        let candidates = try await source.workouts(in: window)
        guard
            let match = matcher.match(
                start: workoutStart,
                end: workoutEnd,
                candidates: candidates,
                claimed: claimed
            )
        else { return nil }
        var summary = try await source.summary(for: match)
        // The source's offsets are relative to the Health workout's start; the app reads them against `workoutStart`.
        // Re-base before downsampling. Offsets may go negative when the Watch workout began earlier; the chart clamps.
        let shift = summary.start.timeIntervalSince(workoutStart)
        let rebased = summary.heartRateSeries.map { HeartRatePoint(offset: $0.offset + shift, bpm: $0.bpm) }
        summary.heartRateSeries = HeartRateSeries.downsample(rebased, maxPoints: maxSeriesPoints)
        return summary
    }
}
