import Foundation
import SwiftData

/// One pass of Fitness enrichment over stored workouts: finds the ones that need a look, matches each against Health,
/// and stores the result.
///
/// `run` is MainActor-isolated (the kit's default isolation): `Workout` is a SwiftData `@Model` and must stay on the
/// actor of its context. Only the source's async calls leave it, because `HealthEnrichment` and `HealthSource` are
/// `nonisolated` and `Sendable`; only `Sendable` values (dates, ids, `HealthWorkoutSummary`) cross the hop, never a
/// model.
public enum HealthEnrichmentRun {
    /// What a pass did.
    public struct Outcome: Equatable, Sendable {
        /// Workouts that got a Fitness match this pass.
        public var matched: Int
        /// Workouts that were looked up and stamped (matched or not).
        public var checked: Int
        /// Set when the pass ended early because Health is unavailable or access is not granted. Workouts from the
        /// failing one onward were not stamped, so a later grant finds them again.
        public var stopped: HealthSourceError?

        public init(matched: Int = 0, checked: Int = 0, stopped: HealthSourceError? = nil) {
            self.matched = matched
            self.checked = checked
            self.stopped = stopped
        }

        public var stoppedForAuthorization: Bool { stopped != nil }
    }

    /// Looks up every workout in `workouts` that `needsHealthCheck` (oldest finish first) and applies what it finds.
    ///
    /// - A Fitness workout already stored on any workout in the list, or matched earlier in this pass, is passed to the
    ///   matcher as claimed, so one Fitness workout never attaches to two of ours.
    /// - `.notAuthorized` and `.unavailable` end the pass; nothing is stamped for that workout or later ones.
    /// - Any other error skips that workout without stamping it, and the pass continues.
    public static func run(
        workouts: [Workout],
        source: any HealthSource,
        now: Date,
        recheckAfter: TimeInterval = 15 * 60
    ) async -> Outcome {
        let pending =
            workouts
            .filter { $0.needsHealthCheck(now: now, recheckAfter: recheckAfter) }
            .sorted { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }
        var claimed = Set(workouts.compactMap(\.healthWorkoutID))
        let enrichment = HealthEnrichment(source: source)
        var outcome = Outcome()

        for workout in pending {
            guard let finishedAt = workout.finishedAt else { continue }
            do {
                let summary = try await enrichment.enrich(
                    workoutStart: workout.startedAt,
                    workoutEnd: finishedAt,
                    claimed: claimed
                )
                workout.applyHealth(summary, checkedAt: now)
                outcome.checked += 1
                if let summary {
                    claimed.insert(summary.healthWorkoutID)
                    outcome.matched += 1
                }
            } catch let error as HealthSourceError {
                switch error {
                case .notAuthorized, .unavailable:
                    outcome.stopped = error
                    return outcome
                case .notFound, .failed:
                    continue
                }
            } catch {
                continue
            }
        }
        return outcome
    }

    /// Finished workouts that finished within `within` of `now`, oldest finish first: what the app fetches to feed
    /// `run`. The default window matches `needsHealthCheck`'s give-up age.
    public static func recentFinishedDescriptor(
        now: Date,
        within: TimeInterval = 7 * 86400
    ) -> FetchDescriptor<Workout> {
        let cutoff = now.addingTimeInterval(-within)
        // Predicates cannot call `Date.distantPast`; a value just before the cutoff stands in for "never finished".
        let beforeCutoff = cutoff.addingTimeInterval(-1)
        return FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.finishedAt != nil && (workout.finishedAt ?? beforeCutoff) >= cutoff
            },
            sortBy: [SortDescriptor(\Workout.finishedAt)]
        )
    }
}
