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
        return await process(
            pending,
            claimedIDs: Set(workouts.compactMap(\.healthWorkoutID)),
            earliest: nil,
            source: source,
            now: now,
            progress: nil
        )
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
        return await process(
            pending,
            claimedIDs: Set(workouts.compactMap(\.healthWorkoutID)),
            earliest: nil,
            source: source,
            now: now,
            progress: progress
        )
    }

    /// `backfill` straight from the store, fetching only what it needs: the never-checked finished workouts
    /// (``backfillCandidatesDescriptor(earliest:)``, limited to what Health can show) and, separately, the Fitness ids already attached (they count as claimed). When
    /// no workout is waiting it returns after a `fetchCount`, without faulting a single model or asking the source anything,
    /// so the foreground backfill is cheap once everything has been stamped.
    public static func backfill(
        context: ModelContext,
        source: any HealthSource,
        now: Date,
        progress: ((_ done: Int, _ total: Int) -> Void)? = nil
    ) async throws -> Outcome {
        // Nothing waiting at all: return without asking the source anything.
        guard try context.fetchCount(backfillCandidatesDescriptor()) > 0 else { return Outcome() }
        // Workouts older than Health's readable window are never stamped (see `process`), so they would stay "waiting"
        // for good. Keep them out of the fetch, or every foreground would fault the whole imported history just to drop it.
        let earliest = await source.earliestReadableDate()
        let candidates = try context.fetch(backfillCandidatesDescriptor(earliest: earliest))
        guard !candidates.isEmpty else { return Outcome() }
        let claimedIDs = try Set(context.fetch(claimedDescriptor()).compactMap(\.healthWorkoutID))
        return await process(
            candidates,
            claimedIDs: claimedIDs,
            earliest: earliest,
            source: source,
            now: now,
            progress: progress
        )
    }

    /// The loop `run` and `backfill` share. `claimedIDs` are the Fitness workouts already attached, which count as claimed.
    ///
    /// Workouts that started before `source.earliestReadableDate()` are dropped first and never stamped: Health cannot show
    /// them (iOS 27 shares only the past 30 days by default), so a lookup would stamp them "unmatched" and a later, wider
    /// grant would never revisit them. `earliest` is that date when the caller already asked for it; `nil` asks the source here.
    private static func process(
        _ candidates: [Workout],
        claimedIDs: Set<String>,
        earliest knownEarliest: Date?,
        source: any HealthSource,
        now: Date,
        progress: ((_ done: Int, _ total: Int) -> Void)?
    ) async -> Outcome {
        // Everything read from the models happens here, before the first `await`: a workout deleted and saved while the
        // pass is suspended is detached afterwards, and reading it then is a fatal error. `stored` records which workouts
        // belong to a context right now (re-checked after each await, see `isLive`); a workout that never had a context
        // (unit tests building bare models) has nothing to be detached from.
        let snapshot = candidates.map { (workout: $0, startedAt: $0.startedAt, stored: $0.modelContext != nil) }
        let earliest: Date
        if let knownEarliest { earliest = knownEarliest } else { earliest = await source.earliestReadableDate() }
        // Only the snapshot's values and liveness are used after the await, never the models' properties.
        let live = snapshot.filter { $0.startedAt >= earliest && Self.isLive($0.workout, wasStored: $0.stored) }
        let pending = live.map(\.workout)
        let stored = live.map(\.stored)
        var claimed = claimedIDs
        let enrichment = HealthEnrichment(source: source)
        var outcome = Outcome()
        let total = pending.count
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
            // What the lookup is about: the window and the health fields as they were when it began. The past-workout
            // editor clears the health fields when it moves the times, so a result for the old window must not land.
            let startedAt = workout.startedAt
            let checkedAtBefore = workout.healthCheckedAt
            let healthIDBefore = workout.healthWorkoutID
            do {
                let summary = try await enrichment.enrich(
                    workoutStart: startedAt,
                    workoutEnd: finishedAt,
                    claimed: claimed
                )
                guard Self.isLive(workout, wasStored: stored[index]),
                    workout.startedAt == startedAt, workout.finishedAt == finishedAt,
                    workout.healthCheckedAt == checkedAtBefore, workout.healthWorkoutID == healthIDBefore
                else {
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
        try resetUnmatched(context: context, save: { try $0.save() })
    }

    /// `resetUnmatched` with the save injectable. If the save throws, every stamp is put back (the context would stay
    /// dirty otherwise, and the next unrelated save would commit the reset despite the error) and the error is rethrown.
    static func resetUnmatched(context: ModelContext, save: (ModelContext) throws -> Void) throws -> Int {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.healthWorkoutID == nil && $0.healthCheckedAt != nil }
        )
        let workouts = try context.fetch(descriptor)
        let stamps = workouts.map(\.healthCheckedAt)
        for workout in workouts { workout.healthCheckedAt = nil }
        do {
            if context.hasChanges { try save(context) }
        } catch {
            for (workout, stamp) in zip(workouts, stamps) { workout.healthCheckedAt = stamp }
            throw error
        }
        return workouts.count
    }

    /// Clears the Fitness data and lookup stamp from every workout that has either, then saves. Returns how many workouts
    /// changed. What "Remove Fitness Data" does.
    @discardableResult
    public static func clearAll(context: ModelContext) throws -> Int {
        try clearAll(context: context, save: { try $0.save() })
    }

    /// `clearAll` with the save injectable. If the save throws, every workout's Fitness fields are put back and the error
    /// is rethrown, so what the failure alert says matches what is stored.
    static func clearAll(context: ModelContext, save: (ModelContext) throws -> Void) throws -> Int {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.healthWorkoutID != nil || $0.healthCheckedAt != nil }
        )
        let workouts = try context.fetch(descriptor)
        let snapshots = workouts.map { $0.healthFieldsSnapshot() }
        for workout in workouts { workout.clearHealth() }
        do {
            if context.hasChanges { try save(context) }
        } catch {
            for (workout, snapshot) in zip(workouts, snapshots) { workout.restoreHealthFields(snapshot) }
            throw error
        }
        return workouts.count
    }

    /// Finished workouts that were never checked and have no Fitness match, oldest finish first: the only ones `backfill`
    /// looks at, so the app never has to fault the rest of the history for it.
    ///
    /// - Parameter earliest: the source's `earliestReadableDate()`; workouts that started before it are left out (Health
    ///   cannot show them, so a pass would drop them unstamped anyway). The default keeps everything.
    public static func backfillCandidatesDescriptor(earliest: Date = .distantPast) -> FetchDescriptor<Workout> {
        FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> {
                $0.finishedAt != nil && $0.healthWorkoutID == nil && $0.healthCheckedAt == nil
                    && $0.startedAt >= earliest
            },
            sortBy: [SortDescriptor(\Workout.finishedAt)]
        )
    }

    /// Workouts that already carry a Fitness workout: their ids are the claimed ones.
    static func claimedDescriptor() -> FetchDescriptor<Workout> {
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate<Workout> { $0.healthWorkoutID != nil })
        descriptor.propertiesToFetch = [\.healthWorkoutID]
        return descriptor
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
