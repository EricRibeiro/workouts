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
        return await process(pending, among: workouts, source: source, now: now, progress: nil)
    }

    /// Looks up every finished, unmatched workout that was never checked (`healthCheckedAt == nil`), however old, oldest
    /// finish first. This is what reaches imported history and workouts from before the person opted in, which `run`
    /// gives up on after a week. A workout already stamped is left alone (matched or not), so each workout is backfilled
    /// once; later passes are `run`'s job. Same rules as `run` for claimed Fitness workouts, a denied or unavailable store
    /// (ends the pass, nothing stamped from there on) and other errors (skipped, not stamped).
    ///
    /// - Parameter progress: called after each workout is handled with `(done, total)`, where `total` is the number
    ///   of workouts this pass will look at.
    public static func backfill(
        workouts: [Workout],
        source: any HealthSource,
        now: Date,
        progress: ((_ done: Int, _ total: Int) -> Void)? = nil
    ) async -> Outcome {
        let pending =
            workouts
            .filter { $0.finishedAt != nil && $0.healthWorkoutID == nil && $0.healthCheckedAt == nil }
            .sorted { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }
        return await process(pending, among: workouts, source: source, now: now, progress: progress)
    }

    /// The loop `run` and `backfill` share. `all` supplies the Fitness workouts already attached, which count as claimed.
    private static func process(
        _ pending: [Workout],
        among all: [Workout],
        source: any HealthSource,
        now: Date,
        progress: ((_ done: Int, _ total: Int) -> Void)?
    ) async -> Outcome {
        var claimed = Set(all.compactMap(\.healthWorkoutID))
        let enrichment = HealthEnrichment(source: source)
        var outcome = Outcome()
        let total = pending.count
        progress?(0, total)

        for (index, workout) in pending.enumerated() {
            // A cancelled pass (Settings turned the feature off) stops here; what it stamped so far stands.
            if Task.isCancelled { return outcome }
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
                    break
                }
            } catch {
                // Skipped without a stamp; the pass goes on.
            }
            progress?(index + 1, total)
        }
        return outcome
    }

    /// Clears the Fitness data and lookup stamp from every workout that has either, then saves. Returns how many workouts
    /// changed. What "Remove Fitness Data" does.
    @discardableResult
    public static func clearAll(context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.healthWorkoutID != nil || $0.healthCheckedAt != nil }
        )
        let workouts = try context.fetch(descriptor)
        for workout in workouts { workout.clearHealth() }
        if context.hasChanges { try context.save() }
        return workouts.count
    }

    /// Every finished workout, oldest finish first: what the app fetches to feed `backfill`.
    public static func allFinishedDescriptor() -> FetchDescriptor<Workout> {
        FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.finishedAt != nil },
            sortBy: [SortDescriptor(\Workout.finishedAt)]
        )
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
