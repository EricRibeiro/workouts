import Foundation

/// Picks the Fitness workout that corresponds to one of our workouts.
///
/// Rules:
/// 1. Only strength kinds (`HealthActivityKind.isStrength`) are candidates.
/// 2. Candidates whose ID is in `claimed` (already attached to another of our workouts) are skipped.
/// 3. Our interval is widened by `slackBefore` (default 10 min) and `slackAfter` (default 15 min), because the Watch is
///    started and stopped at different moments than this app. A candidate must overlap the widened window, and must also
///    overlap our actual interval by more than zero.
/// 4. The overlap score is the length of the candidate's intersection with the widened window.
/// 5. A candidate is rejected when that overlap is under `minimumOverlapRatio` (default 40%) of the shorter of the two
///    durations (ours, the candidate's).
/// 6. Among the rest, the largest overlap wins; ties go to the start closest to ours, then to the lower ID.
public nonisolated struct HealthMatcher: Sendable {
    public var slackBefore: TimeInterval
    public var slackAfter: TimeInterval
    public var minimumOverlapRatio: Double

    public static let defaultSlackBefore: TimeInterval = 10 * 60
    public static let defaultSlackAfter: TimeInterval = 15 * 60
    public static let defaultMinimumOverlapRatio = 0.4

    public init(
        slackBefore: TimeInterval = HealthMatcher.defaultSlackBefore,
        slackAfter: TimeInterval = HealthMatcher.defaultSlackAfter,
        minimumOverlapRatio: Double = HealthMatcher.defaultMinimumOverlapRatio
    ) {
        self.slackBefore = slackBefore
        self.slackAfter = slackAfter
        self.minimumOverlapRatio = minimumOverlapRatio
    }

    /// Our workout's interval widened by the slack: what to query Health for, and what overlap is measured against.
    public func window(start: Date, end: Date) -> DateInterval {
        let end = max(start, end)
        return DateInterval(
            start: start.addingTimeInterval(-slackBefore),
            end: end.addingTimeInterval(slackAfter)
        )
    }

    /// The best candidate for a workout from `start` to `end`, or nil.
    public func match(
        start: Date,
        end: Date,
        candidates: [HealthWorkoutCandidate],
        claimed: Set<String> = []
    ) -> HealthWorkoutCandidate? {
        let end = max(start, end)
        let ours = DateInterval(start: start, end: end)
        let widened = window(start: start, end: end)

        var best: (candidate: HealthWorkoutCandidate, overlap: TimeInterval, startGap: TimeInterval)?
        for candidate in candidates where candidate.kind.isStrength && !claimed.contains(candidate.id) {
            let theirs = candidate.interval
            guard Self.overlap(theirs, ours) > 0 else { continue }
            let overlap = Self.overlap(theirs, widened)
            let shorter = min(ours.duration, theirs.duration)
            guard shorter > 0, overlap >= minimumOverlapRatio * shorter else { continue }
            let gap = abs(candidate.start.timeIntervalSince(start))
            if let current = best {
                let better =
                    overlap > current.overlap
                    || (overlap == current.overlap
                        && (gap < current.startGap
                            || (gap == current.startGap && candidate.id < current.candidate.id)))
                if !better { continue }
            }
            best = (candidate, overlap, gap)
        }
        return best?.candidate
    }

    private static func overlap(_ a: DateInterval, _ b: DateInterval) -> TimeInterval {
        a.intersection(with: b)?.duration ?? 0
    }
}
