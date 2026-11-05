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
        /// Set when the pass ended early because Health is unavailable (or a source reported `.notAuthorized`; the real
        /// HealthKit source cannot, since a denied read comes back as "no data"). Workouts from the failing one onward
        /// were not stamped, so a later pass finds them again.
        public var stopped: HealthSourceError?

        public init(matched: Int = 0, checked: Int = 0, stopped: HealthSourceError? = nil) {
            self.matched = matched
            self.checked = checked
            self.stopped = stopped
        }
    }

    /// Looks up every workout in `workouts` that `needsHealthCheck` (oldest finish first) and applies what it finds.
    ///
    /// - A Fitness workout already stored on any workout in the list, or matched earlier in this pass, is passed to the
    ///   matcher as claimed, so one Fitness workout never attaches to two of ours.
    /// - `.unavailable` ends the pass; nothing is stamped for that workout or later ones. (`.notAuthorized` ends it the
    ///   same way, but only a fake source throws it: HealthKit reports a denied read as an empty answer, so a denied
    ///   store stamps workouts as unmatched. `resetUnmatched` is how an opt-in recovers from that.)
    /// - A workout deleted or detached while the pass awaited is skipped, never stamped.
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
    /// once; later passes are `run`'s job. Same rules as `run` for claimed Fitness workouts, an unavailable store (ends
    /// the pass, nothing stamped from there on), deleted workouts and other errors (skipped, not stamped). A store the
    /// person denied looks empty to HealthKit, so it stamps everything as unmatched; `resetUnmatched` undoes that.
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
            .filter { $0.isFinished && $0.healthWorkoutID == nil && $0.healthCheckedAt == nil }
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
        // Which workouts belong to a context right now. Stored ones are re-checked after each await (see `isLive`); a
        // workout that never had a context (unit tests building bare models) has nothing to be detached from.
        let stored = pending.map { $0.modelContext != nil }
        progress?(0, total)

        for (index, workout) in pending.enumerated() {
            // A cancelled pass (Settings turned the feature off) stops here; what it stamped so far stands.
            if Task.isCancelled { return outcome }
            // The pass awaits the source with models in hand; a workout deleted and saved meanwhile is detached, and reading
            // or writing it is unsafe. Checked before the first read and again before the write below.
            guard Self.isLive(workout, wasStored: stored[index]) else {
                progress?(index + 1, total)
                continue
            }
            guard let finishedAt = workout.finishedAt else { continue }
            do {
                let summary = try await enrichment.enrich(
                    workoutStart: workout.startedAt,
                    workoutEnd: finishedAt,
                    claimed: claimed
                )
                guard Self.isLive(workout, wasStored: stored[index]) else {
                    progress?(index + 1, total)
                    continue
                }
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

    /// Whether `workout` is still usable: not deleted, and, if it was stored when the pass began, still attached to its
    /// context (a deleted-and-saved model is detached, and touching its properties is unsafe).
    private static func isLive(_ workout: Workout, wasStored: Bool) -> Bool {
        !workout.isDeleted && (!wasStored || workout.modelContext != nil)
    }

    /// Clears the lookup stamp from every workout that was checked but not matched, then saves, so the next backfill looks
    /// at them again. Matches are kept. Returns how many workouts changed.
    ///
    /// HealthKit never says whether a read was denied: a denied type simply answers "no workouts", so a pass run before
    /// the person granted access stamps the whole history as unmatched and `backfill` would never revisit it. The app
    /// calls this on every opt-in, so each opt-in is a fresh look.
    @discardableResult
    public static func resetUnmatched(context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.healthWorkoutID == nil && $0.healthCheckedAt != nil }
        )
        let workouts = try context.fetch(descriptor)
        for workout in workouts { workout.healthCheckedAt = nil }
        if context.hasChanges { try context.save() }
        return workouts.count
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
            predicate: Workout.finishedPredicate,
            sortBy: [SortDescriptor(\Workout.finishedAt)]
        )
    }

    /// Finished workouts that finished within `within` of `now`, oldest finish first: what the app fetches to feed
    /// `run`. The default window matches `needsHealthCheck`'s give-up age.
    public static func recentFinishedDescriptor(
        now: Date,
        within: TimeInterval = 7 * 86400
    ) -> FetchDescriptor<Workout> {
        FetchDescriptor<Workout>(
            predicate: Workout.finishedPredicate(since: now.addingTimeInterval(-within)),
            sortBy: [SortDescriptor(\Workout.finishedAt)]
        )
    }
}
