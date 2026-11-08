import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

/// A source that can fail per call: `summary` throws for the listed candidate ids, and `workouts(in:)` throws for
/// windows starting at or after `failWindowsStartingAt`.
private nonisolated struct FlakySource: HealthSource {
    var base: FakeHealthSource
    var failSummaryFor: [String: HealthSourceError] = [:]
    var failWindowsStartingAt: (date: Date, error: HealthSourceError)?

    func workouts(in interval: DateInterval) async throws -> [HealthWorkoutCandidate] {
        if let failWindowsStartingAt, interval.start >= failWindowsStartingAt.date {
            throw failWindowsStartingAt.error
        }
        return try await base.workouts(in: interval)
    }

    func summary(for candidate: HealthWorkoutCandidate) async throws -> HealthWorkoutSummary {
        if let error = failSummaryFor[candidate.id] { throw error }
        return try await base.summary(for: candidate)
    }
}

/// Lets a test hold a source call open until `release()`: `waitUntilEntered()` returns once a call is suspended inside the
/// source, so the test can act while a pass is in flight with no timing involved. After `release()` calls pass straight through.
private actor Gate {
    private var entered = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters = []
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// Suspends every `workouts(in:)` call at the gate, then answers from `base`.
private nonisolated struct GatedSource: HealthSource {
    let gate: Gate
    let base: FakeHealthSource

    func workouts(in interval: DateInterval) async throws -> [HealthWorkoutCandidate] {
        await gate.wait()
        return try await base.workouts(in: interval)
    }

    func summary(for candidate: HealthWorkoutCandidate) async throws -> HealthWorkoutSummary {
        try await base.summary(for: candidate)
    }
}

/// Suspends `earliestReadableDate()` at the gate (the pass's first await), then answers from `base`. Counts every call, so
/// a test can tell whether a pass reached the source at all.
private nonisolated struct EarliestGatedSource: HealthSource {
    let gate: Gate
    let base: FakeHealthSource
    let calls: Counter

    func earliestReadableDate() async -> Date {
        await calls.bump()
        await gate.wait()
        return await base.earliestReadableDate()
    }

    func workouts(in interval: DateInterval) async throws -> [HealthWorkoutCandidate] {
        try await base.workouts(in: interval)
    }

    func summary(for candidate: HealthWorkoutCandidate) async throws -> HealthWorkoutSummary {
        try await base.summary(for: candidate)
    }
}

private actor Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}

@Suite struct HealthEnrichmentRunTests {
    private typealias Outcome = HealthEnrichmentRun.Outcome

    private static let t0 = TestSupport.referenceDate
    private static let now = t0.addingTimeInterval(86400)

    /// A finished 50-minute workout starting `startOffset` seconds after t0.
    private static func workout(startOffset: TimeInterval = 0, name: String = "Push") -> Workout {
        let start = t0.addingTimeInterval(startOffset)
        return Workout(name: name, startedAt: start, finishedAt: start.addingTimeInterval(3000), updatedAt: t0)
    }

    private static func summary(_ id: String, startOffset: TimeInterval = 0) -> HealthWorkoutSummary {
        let start = t0.addingTimeInterval(startOffset)
        return HealthWorkoutSummary(
            healthWorkoutID: id,
            start: start,
            end: start.addingTimeInterval(3000),
            activeEnergyKcal: 300,
            avgHeartRate: 120
        )
    }

    /// A fake Health store holding 50-minute strength workouts with the given ids and start offsets.
    private static func source(_ entries: [(id: String, startOffset: TimeInterval)]) -> FakeHealthSource {
        FakeHealthSource(
            candidates: entries.map { entry in
                let start = t0.addingTimeInterval(entry.startOffset)
                return HealthWorkoutCandidate(
                    id: entry.id,
                    kind: .traditionalStrength,
                    start: start,
                    end: start.addingTimeInterval(3000)
                )
            },
            summaries: entries.map { summary($0.id, startOffset: $0.startOffset) }
        )
    }

    // MARK: Matching

    @Test func matchesAndStamps() async {
        let workout = Self.workout()
        let outcome = await HealthEnrichmentRun.run(
            workouts: [workout],
            source: Self.source([("HK-1", 0)]),
            now: Self.now
        )
        #expect(outcome == Outcome(matched: 1, checked: 1, stopped: nil))
        #expect(workout.healthWorkoutID == "HK-1")
        #expect(workout.avgHeartRate == 120)
        #expect(workout.healthCheckedAt == Self.now)
        #expect(workout.updatedAt == Self.t0)
    }

    @Test func noCandidateStampsOnly() async {
        let workout = Self.workout()
        let outcome = await HealthEnrichmentRun.run(workouts: [workout], source: FakeHealthSource(), now: Self.now)
        #expect(outcome == Outcome(matched: 0, checked: 1, stopped: nil))
        #expect(workout.healthWorkoutID == nil)
        #expect(workout.healthCheckedAt == Self.now)
    }

    @Test func oneFitnessWorkoutNeverMatchesTwoOfOurs() async {
        // Two overlapping workouts, one Fitness candidate: the older finish takes it, the other is stamped unmatched.
        let first = Self.workout(startOffset: 0, name: "A")
        let second = Self.workout(startOffset: 600, name: "B")
        let outcome = await HealthEnrichmentRun.run(
            workouts: [second, first],
            source: Self.source([("HK-1", 0)]),
            now: Self.now
        )
        #expect(outcome == Outcome(matched: 1, checked: 2, stopped: nil))
        #expect(first.healthWorkoutID == "HK-1")
        #expect(second.healthWorkoutID == nil)
        #expect(second.healthCheckedAt == Self.now)
    }

    @Test func eachGetsItsOwnWhenTwoCandidatesExist() async {
        let first = Self.workout(startOffset: 0)
        let second = Self.workout(startOffset: 600)
        let outcome = await HealthEnrichmentRun.run(
            workouts: [first, second],
            source: Self.source([("HK-1", 0), ("HK-2", 600)]),
            now: Self.now
        )
        #expect(outcome == Outcome(matched: 2, checked: 2, stopped: nil))
        #expect(first.healthWorkoutID == "HK-1")
        #expect(second.healthWorkoutID == "HK-2")
    }

    @Test func idAlreadyStoredOnAnotherWorkoutIsClaimed() async {
        let matched = Self.workout(startOffset: 0)
        matched.applyHealth(Self.summary("HK-1"), checkedAt: Self.t0)
        let fresh = Self.workout(startOffset: 600)
        let outcome = await HealthEnrichmentRun.run(
            workouts: [matched, fresh],
            source: Self.source([("HK-1", 0)]),
            now: Self.now
        )
        #expect(outcome == Outcome(matched: 0, checked: 1, stopped: nil))
        #expect(fresh.healthWorkoutID == nil)
        #expect(fresh.healthCheckedAt == Self.now)
        #expect(matched.healthWorkoutID == "HK-1")
    }

    @Test func oldestFinishGoesFirst() async {
        // The newer workout is listed first, but the older finish gets the single candidate.
        let older = Self.workout(startOffset: 0, name: "older")
        let newer = Self.workout(startOffset: 300, name: "newer")
        _ = await HealthEnrichmentRun.run(
            workouts: [newer, older],
            source: Self.source([("HK-1", 150)]),
            now: Self.now
        )
        #expect(older.healthWorkoutID == "HK-1")
        #expect(newer.healthWorkoutID == nil)
    }

    // MARK: Errors

    // `.notAuthorized` is fake-only behaviour: the real HealthKit source never throws it (a denied read comes back as an
    // empty answer, see `resetUnmatched`). These tests pin the run's handling of any source that does.
    @Test func notAuthorizedFromASourceStopsAndStampsNothing() async {
        let a = Self.workout(startOffset: 0)
        let b = Self.workout(startOffset: 7200)
        let outcome = await HealthEnrichmentRun.run(
            workouts: [a, b],
            source: FakeHealthSource.failing(.notAuthorized),
            now: Self.now
        )
        #expect(outcome == Outcome(matched: 0, checked: 0, stopped: .notAuthorized))
        #expect(a.healthCheckedAt == nil && b.healthCheckedAt == nil)
    }

    @Test func unavailableStopsTheWholeRunKeepingEarlierWork() async {
        // The oldest workout succeeds; the second hits `.unavailable`, and the third is never tried.
        let a = Self.workout(startOffset: 0)
        let b = Self.workout(startOffset: 7200)
        let c = Self.workout(startOffset: 14400)
        let source = FlakySource(
            base: Self.source([("HK-1", 0)]),
            // Query windows start 10 minutes before the workout.
            failWindowsStartingAt: (Self.t0.addingTimeInterval(7200 - 600), .unavailable)
        )
        let outcome = await HealthEnrichmentRun.run(workouts: [c, b, a], source: source, now: Self.now)
        #expect(outcome == Outcome(matched: 1, checked: 1, stopped: .unavailable))
        #expect(a.healthWorkoutID == "HK-1")
        #expect(b.healthCheckedAt == nil && c.healthCheckedAt == nil)
    }

    @Test func otherErrorSkipsOnlyThatWorkout() async {
        // a's lookup fails; b is fine. a stays unstamped so a later pass retries it.
        let a = Self.workout(startOffset: 0)
        let b = Self.workout(startOffset: 7200)
        let source = FlakySource(
            base: Self.source([("HK-1", 0), ("HK-2", 7200)]),
            failSummaryFor: ["HK-1": .failed("boom")]
        )
        let outcome = await HealthEnrichmentRun.run(workouts: [a, b], source: source, now: Self.now)
        #expect(outcome == Outcome(matched: 1, checked: 1, stopped: nil))
        #expect(a.healthWorkoutID == nil && a.healthCheckedAt == nil)
        #expect(b.healthWorkoutID == "HK-2")
        #expect(b.healthCheckedAt == Self.now)
    }

    @Test func clearAllWipesMatchedAndStampedWorkoutsOnly() throws {
        let context = try makeTestContext()
        let matched = Self.workout(startOffset: 0)
        matched.applyHealth(Self.summary("HK-1"), checkedAt: Self.t0)
        let stamped = Self.workout(startOffset: 7200)
        stamped.applyHealth(nil, checkedAt: Self.t0)
        let untouched = Self.workout(startOffset: 14400)
        for workout in [matched, stamped, untouched] { context.insert(workout) }
        try context.save()

        #expect(try HealthEnrichmentRun.clearAll(context: context) == 2)
        #expect(matched.healthWorkoutID == nil && matched.healthCheckedAt == nil && matched.activeEnergyKcal == nil)
        #expect(stamped.healthCheckedAt == nil)
        #expect(matched.updatedAt == Self.t0)
        #expect(!context.hasChanges)
        #expect(try HealthEnrichmentRun.clearAll(context: context) == 0)
    }

    @Test func clearAllPutsEverythingBackWhenTheSaveFails() throws {
        let context = try makeTestContext()
        let matched = Self.workout(startOffset: 0)
        matched.applyHealth(Self.summary("HK-1"), checkedAt: Self.t0)
        let stamped = Self.workout(startOffset: 7200)
        stamped.applyHealth(nil, checkedAt: Self.t0)
        for workout in [matched, stamped] { context.insert(workout) }
        try context.save()

        #expect(throws: HealthSaveFailed.self) {
            try HealthEnrichmentRun.clearAll(context: context, save: { _ in throw HealthSaveFailed() })
        }
        #expect(matched.healthWorkoutID == "HK-1" && matched.healthCheckedAt == Self.t0)
        #expect(matched.activeEnergyKcal == 300 && matched.avgHeartRate == 120)
        #expect(stamped.healthCheckedAt == Self.t0)
        // A later, unrelated save commits what was stored all along, not the removal.
        try context.save()
        #expect(matched.healthWorkoutID == "HK-1" && stamped.healthCheckedAt == Self.t0)
    }

    // MARK: Deleted mid-pass

    /// Three finished workouts in a real context, each with its own Fitness workout, behind a source whose lookups wait at
    /// a gate until the test releases it.
    private func gatedPassFixture() throws -> (
        context: ModelContext, workouts: [Workout], source: GatedSource, gate: Gate
    ) {
        let context = try makeTestContext()
        let workouts = [0.0, 7200, 14400].map { Self.workout(startOffset: $0) }
        for workout in workouts { context.insert(workout) }
        try context.save()
        let gate = Gate()
        let source = GatedSource(gate: gate, base: Self.source([("HK-1", 0), ("HK-2", 7200), ("HK-3", 14400)]))
        return (context, workouts, source, gate)
    }

    @Test func aPendingWorkoutDeletedMidPassIsNeverStamped() async throws {
        let (context, workouts, source, gate) = try gatedPassFixture()
        let pass = Task { await HealthEnrichmentRun.backfill(workouts: workouts, source: source, now: Self.later) }
        // The first workout is suspended inside the source; delete the second, which is still pending.
        await gate.waitUntilEntered()
        context.delete(workouts[1])
        try context.save()
        await gate.release()
        let outcome = await pass.value

        #expect(outcome == Outcome(matched: 2, checked: 2, stopped: nil))
        #expect(workouts[0].healthWorkoutID == "HK-1")
        #expect(workouts[2].healthWorkoutID == "HK-3")
        #expect(workouts[1].healthWorkoutID == nil && workouts[1].healthCheckedAt == nil)
    }

    @Test func theWorkoutBeingLookedUpDeletedMidPassIsNeverStamped() async throws {
        let (context, workouts, source, gate) = try gatedPassFixture()
        let pass = Task { await HealthEnrichmentRun.run(workouts: workouts, source: source, now: Self.now) }
        // The first workout's lookup is suspended inside the source; delete it before the answer comes back.
        await gate.waitUntilEntered()
        context.delete(workouts[0])
        try context.save()
        await gate.release()
        let outcome = await pass.value

        #expect(outcome == Outcome(matched: 2, checked: 2, stopped: nil))
        #expect(workouts[0].healthWorkoutID == nil && workouts[0].healthCheckedAt == nil)
        #expect(workouts[1].healthWorkoutID == "HK-2")
        #expect(workouts[2].healthWorkoutID == "HK-3")
    }

    @Test func aWorkoutWhoseTimesChangeDuringTheLookupIsNeitherAppliedNorStamped() async throws {
        let (context, workouts, source, gate) = try gatedPassFixture()
        let pass = Task { await HealthEnrichmentRun.run(workouts: [workouts[0]], source: source, now: Self.now) }
        // The lookup for the original window is suspended inside the source; the past-workout editor then moves the
        // times and clears the health fields, as it does for real.
        await gate.waitUntilEntered()
        workouts[0].startedAt = Self.t0.addingTimeInterval(3 * 86400)
        workouts[0].finishedAt = Self.t0.addingTimeInterval(3 * 86400 + 3000)
        workouts[0].healthWorkoutID = nil
        workouts[0].healthCheckedAt = nil
        try context.save()
        await gate.release()
        let outcome = await pass.value

        #expect(outcome == Outcome(matched: 0, checked: 0, stopped: nil))
        #expect(workouts[0].healthWorkoutID == nil && workouts[0].healthCheckedAt == nil)
    }

    @Test func aWorkoutDeletedDuringTheFirstAwaitIsSkippedWithoutBeingTouched() async throws {
        let context = try makeTestContext()
        let workouts = [0.0, 7200].map { Self.workout(startOffset: $0) }
        for workout in workouts { context.insert(workout) }
        try context.save()
        let gate = Gate()
        let calls = Counter()
        let source = EarliestGatedSource(
            gate: gate,
            base: Self.source([("HK-1", 0), ("HK-2", 7200)]),
            calls: calls
        )
        var done: [Int] = []
        let pass = Task {
            await HealthEnrichmentRun.backfill(
                workouts: workouts,
                source: source,
                now: Self.later,
                progress: { finished, _ in done.append(finished) }
            )
        }
        // The pass is suspended in `earliestReadableDate()`, before it has looked at a single workout; delete one there.
        await gate.waitUntilEntered()
        context.delete(workouts[0])
        try context.save()
        await gate.release()
        let outcome = await pass.value

        // The deleted workout is dropped (it was snapshotted as stored, so it is not mistaken for a bare model), is not
        // counted in the total, and nothing was written to it.
        #expect(outcome == Outcome(matched: 1, checked: 1, stopped: nil))
        #expect(workouts[1].healthWorkoutID == "HK-2")
        #expect(done == [0, 1])
    }

    @Test func aBackfillWithNothingPendingDoesNotFetchWorkoutsOrAskTheSource() async throws {
        let context = try makeTestContext()
        let matched = Self.workout(startOffset: 0)
        matched.healthWorkoutID = "HK-1"
        matched.healthCheckedAt = Self.t0
        let checked = Self.workout(startOffset: 7200)
        checked.healthCheckedAt = Self.t0
        let active = Workout(name: "active", startedAt: Self.t0, updatedAt: Self.t0)
        for workout in [matched, checked, active] { context.insert(workout) }
        try context.save()
        let gate = Gate()
        await gate.release()
        let calls = Counter()
        let source = EarliestGatedSource(gate: gate, base: Self.source([("HK-9", 14400)]), calls: calls)

        #expect(try context.fetchCount(HealthEnrichmentRun.backfillCandidatesDescriptor()) == 0)
        let outcome = try await HealthEnrichmentRun.backfill(context: context, source: source, now: Self.later)

        #expect(outcome == Outcome())
        #expect(await calls.value == 0)
        #expect(!context.hasChanges)
    }

    @Test func aContextBackfillFetchesOnlyTheNeverCheckedAndHonoursClaimedIDs() async throws {
        let context = try makeTestContext()
        // Already holds HK-1, so the pending one must not take it; the checked one is left alone.
        let holder = Self.workout(startOffset: 0, name: "holder")
        holder.healthWorkoutID = "HK-1"
        holder.healthCheckedAt = Self.t0
        let checked = Self.workout(startOffset: 3600, name: "checked")
        checked.healthCheckedAt = Self.t0
        let pending = Self.workout(startOffset: 7200, name: "pending")
        for workout in [holder, checked, pending] { context.insert(workout) }
        try context.save()
        let source = Self.source([("HK-1", 7200)])

        #expect(
            try context.fetch(HealthEnrichmentRun.backfillCandidatesDescriptor()).map(\.name) == ["pending"]
        )
        let outcome = try await HealthEnrichmentRun.backfill(context: context, source: source, now: Self.later)

        #expect(outcome == Outcome(matched: 0, checked: 1, stopped: nil))
        #expect(pending.healthWorkoutID == nil && pending.healthCheckedAt == Self.later)
        #expect(checked.healthCheckedAt == Self.t0)
    }

    @Test func backfillProgressStillReachesTheTotalWhenAWorkoutWasDeleted() async throws {
        let (context, workouts, source, gate) = try gatedPassFixture()
        var done: [Int] = []
        let pass = Task {
            await HealthEnrichmentRun.backfill(
                workouts: workouts,
                source: source,
                now: Self.later,
                progress: { finished, _ in done.append(finished) }
            )
        }
        await gate.waitUntilEntered()
        context.delete(workouts[2])
        try context.save()
        await gate.release()
        _ = await pass.value
        #expect(done.last == 3)
    }

    // MARK: Reset

    @Test func resetUnmatchedClearsOnlyTheStampsOfUnmatchedWorkouts() throws {
        let context = try makeTestContext()
        let matched = Self.workout(startOffset: 0)
        matched.applyHealth(Self.summary("HK-1"), checkedAt: Self.t0)
        let stamped = Self.workout(startOffset: 7200)
        stamped.applyHealth(nil, checkedAt: Self.t0)
        let untouched = Self.workout(startOffset: 14400)
        for workout in [matched, stamped, untouched] { context.insert(workout) }
        try context.save()

        #expect(try HealthEnrichmentRun.resetUnmatched(context: context) == 1)
        #expect(stamped.healthCheckedAt == nil)
        #expect(matched.healthWorkoutID == "HK-1" && matched.healthCheckedAt == Self.t0)
        #expect(matched.activeEnergyKcal == 300)
        #expect(untouched.healthCheckedAt == nil)
        #expect(stamped.updatedAt == Self.t0)
        #expect(!context.hasChanges)
        #expect(try HealthEnrichmentRun.resetUnmatched(context: context) == 0)
    }

    @Test func resetUnmatchedPutsTheStampsBackWhenTheSaveFails() throws {
        let context = try makeTestContext()
        let stamped = Self.workout(startOffset: 7200)
        stamped.applyHealth(nil, checkedAt: Self.t0)
        context.insert(stamped)
        try context.save()

        #expect(throws: HealthSaveFailed.self) {
            try HealthEnrichmentRun.resetUnmatched(context: context, save: { _ in throw HealthSaveFailed() })
        }
        #expect(stamped.healthCheckedAt == Self.t0)
    }

    @Test func aContextBackfillLeavesOutWorkoutsFromBeforeTheReadableWindow() async throws {
        let context = try makeTestContext()
        let tooOld = Self.workout(startOffset: 0, name: "tooOld")
        let readable = Self.workout(startOffset: 7200, name: "readable")
        for workout in [tooOld, readable] { context.insert(workout) }
        try context.save()
        let earliest = Self.t0.addingTimeInterval(3600)

        #expect(
            try context.fetch(HealthEnrichmentRun.backfillCandidatesDescriptor(earliest: earliest)).map(\.name)
                == ["readable"]
        )
        // Starting exactly at the boundary counts as readable.
        let boundary = HealthEnrichmentRun.backfillCandidatesDescriptor(earliest: Self.t0.addingTimeInterval(7200))
        #expect(try context.fetch(boundary).map(\.name) == ["readable"])

        var fake = Self.source([("HK-1", 0), ("HK-2", 7200)])
        fake.earliestReadable = earliest
        let outcome = try await HealthEnrichmentRun.backfill(context: context, source: fake, now: Self.later)
        #expect(outcome == Outcome(matched: 1, checked: 1, stopped: nil))
        #expect(tooOld.healthCheckedAt == nil && tooOld.healthWorkoutID == nil)
        #expect(readable.healthWorkoutID == "HK-2")

        // With only too-old workouts left, nothing is fetched and the source is not asked to look anything up.
        let again = try await HealthEnrichmentRun.backfill(context: context, source: fake, now: Self.later)
        #expect(again == Outcome())
    }

    @Test func aResetWorkoutIsBackfilledAgainOnceHealthHasItsMatch() async throws {
        let context = try makeTestContext()
        let workout = Self.workout()
        context.insert(workout)
        try context.save()

        // A denied store answers "no data": the workout is stamped unmatched and the backfill will not look again.
        _ = await HealthEnrichmentRun.backfill(workouts: [workout], source: FakeHealthSource(), now: Self.later)
        let skipped = await HealthEnrichmentRun.backfill(
            workouts: [workout],
            source: Self.source([("HK-1", 0)]),
            now: Self.later
        )
        #expect(skipped == Outcome() && workout.healthWorkoutID == nil)

        try HealthEnrichmentRun.resetUnmatched(context: context)
        let outcome = await HealthEnrichmentRun.backfill(
            workouts: [workout],
            source: Self.source([("HK-1", 0)]),
            now: Self.later
        )
        #expect(outcome == Outcome(matched: 1, checked: 1, stopped: nil))
        #expect(workout.healthWorkoutID == "HK-1")
    }

    // MARK: Which workouts are picked

    @Test func unfinishedMatchedAndRecentlyCheckedAreSkipped() async {
        let unfinished = Workout(name: "Live", startedAt: Self.t0, updatedAt: Self.t0)
        let matched = Self.workout(startOffset: 0)
        matched.applyHealth(Self.summary("HK-9"), checkedAt: Self.t0)
        let recent = Self.workout(startOffset: 0)
        recent.healthCheckedAt = Self.now.addingTimeInterval(-5 * 60)
        let stale = Self.workout(startOffset: 0)
        stale.healthCheckedAt = Self.now.addingTimeInterval(-20 * 60)

        let outcome = await HealthEnrichmentRun.run(
            workouts: [unfinished, matched, recent, stale],
            source: Self.source([("HK-1", 0)]),
            now: Self.now
        )
        #expect(outcome == Outcome(matched: 1, checked: 1, stopped: nil))
        #expect(unfinished.healthCheckedAt == nil)
        #expect(matched.healthWorkoutID == "HK-9")
        #expect(recent.healthCheckedAt == Self.now.addingTimeInterval(-5 * 60) && recent.healthWorkoutID == nil)
        #expect(stale.healthWorkoutID == "HK-1")
    }

    @Test func customRecheckIntervalIsHonoured() async {
        let workout = Self.workout()
        workout.healthCheckedAt = Self.now.addingTimeInterval(-5 * 60)
        let outcome = await HealthEnrichmentRun.run(
            workouts: [workout],
            source: FakeHealthSource(),
            now: Self.now,
            recheckAfter: 60
        )
        #expect(outcome.checked == 1)
    }

    @Test func workoutsOlderThanAWeekAreNotChased() async {
        let old = Self.workout()
        let outcome = await HealthEnrichmentRun.run(
            workouts: [old],
            source: Self.source([("HK-1", 0)]),
            now: Self.t0.addingTimeInterval(9 * 86400)
        )
        #expect(outcome == Outcome())
        #expect(old.healthCheckedAt == nil)
    }

    // MARK: Descriptor

    @Test func descriptorReturnsFinishedInWindowOldestFirst() throws {
        let context = try makeTestContext()
        let now = Self.t0.addingTimeInterval(10 * 86400)
        func finished(daysAgo: Double, name: String) -> Workout {
            let end = now.addingTimeInterval(-daysAgo * 86400)
            return Workout(name: name, startedAt: end.addingTimeInterval(-3000), finishedAt: end, updatedAt: Self.t0)
        }
        let newest = finished(daysAgo: 0.5, name: "newest")
        let middle = finished(daysAgo: 3, name: "middle")
        let edge = finished(daysAgo: 6.9, name: "edge")
        let tooOld = finished(daysAgo: 8, name: "tooOld")
        let active = Workout(name: "active", startedAt: now.addingTimeInterval(-600), updatedAt: Self.t0)
        for workout in [newest, tooOld, active, middle, edge] { context.insert(workout) }
        try context.save()

        let names = try context.fetch(HealthEnrichmentRun.recentFinishedDescriptor(now: now)).map(\.name)
        #expect(names == ["edge", "middle", "newest"])

        let narrow = try context.fetch(HealthEnrichmentRun.recentFinishedDescriptor(now: now, within: 86400))
        #expect(narrow.map(\.name) == ["newest"])
    }

    // MARK: Backfill

    /// `now` a year after t0: the workouts below are far past `run`'s seven-day give-up.
    private static let later = t0.addingTimeInterval(365 * 86400)

    @Test func backfillMatchesAnOldNeverCheckedWorkout() async {
        let old = Self.workout()
        // Proof of the premise: the routine pass leaves it alone.
        let routine = await HealthEnrichmentRun.run(
            workouts: [old],
            source: Self.source([("HK-1", 0)]),
            now: Self.later
        )
        #expect(routine == Outcome())
        #expect(old.healthCheckedAt == nil)

        let outcome = await HealthEnrichmentRun.backfill(
            workouts: [old],
            source: Self.source([("HK-1", 0)]),
            now: Self.later
        )
        #expect(outcome == Outcome(matched: 1, checked: 1, stopped: nil))
        #expect(old.healthWorkoutID == "HK-1")
        #expect(old.healthCheckedAt == Self.later)
    }

    @Test func backfillSkipsWithoutStampingWorkoutsBeforeTheEarliestReadableDateThenMatchesOnceItWidens() async {
        let old = Self.workout()
        let recent = Self.workout(startOffset: 40 * 86400, name: "Pull")
        var source = Self.source([("HK-1", 0), ("HK-2", 40 * 86400)])
        source.earliestReadable = Self.t0.addingTimeInterval(30 * 86400)
        var progress: [Int] = []

        let narrow = await HealthEnrichmentRun.backfill(
            workouts: [old, recent],
            source: source,
            now: Self.later,
            progress: { _, total in progress.append(total) }
        )
        #expect(narrow == Outcome(matched: 1, checked: 1, stopped: nil))
        #expect(old.healthWorkoutID == nil)
        #expect(old.healthCheckedAt == nil)
        #expect(recent.healthWorkoutID == "HK-2")
        #expect(Set(progress) == [1])

        source.earliestReadable = .distantPast
        let wide = await HealthEnrichmentRun.backfill(workouts: [old, recent], source: source, now: Self.later)
        #expect(wide == Outcome(matched: 1, checked: 1, stopped: nil))
        #expect(old.healthWorkoutID == "HK-1")
        #expect(old.healthCheckedAt == Self.later)
    }

    @Test func routinePassSkipsWithoutStampingWorkoutsBeforeTheEarliestReadableDate() async {
        let workout = Self.workout()
        let now = Self.t0.addingTimeInterval(86400)
        var source = Self.source([("HK-1", 0)])
        source.earliestReadable = Self.t0.addingTimeInterval(1)

        let narrow = await HealthEnrichmentRun.run(workouts: [workout], source: source, now: now)
        #expect(narrow == Outcome())
        #expect(workout.healthCheckedAt == nil)

        source.earliestReadable = .distantPast
        let wide = await HealthEnrichmentRun.run(workouts: [workout], source: source, now: now)
        #expect(wide == Outcome(matched: 1, checked: 1, stopped: nil))
        #expect(workout.healthWorkoutID == "HK-1")
    }

    @Test func backfillStampsAnOldWorkoutWithNoMatchSoItIsNotChasedAgain() async {
        let old = Self.workout()
        let outcome = await HealthEnrichmentRun.backfill(
            workouts: [old],
            source: FakeHealthSource(),
            now: Self.later
        )
        #expect(outcome == Outcome(matched: 0, checked: 1, stopped: nil))
        #expect(old.healthWorkoutID == nil)
        #expect(old.healthCheckedAt == Self.later)

        // A second backfill, now that Health has the workout, still leaves it: once per workout.
        let again = await HealthEnrichmentRun.backfill(
            workouts: [old],
            source: Self.source([("HK-1", 0)]),
            now: Self.later.addingTimeInterval(60)
        )
        #expect(again == Outcome())
        #expect(old.healthWorkoutID == nil)
        #expect(old.healthCheckedAt == Self.later)
    }

    @Test func backfillSkipsAnAlreadyCheckedWorkout() async {
        let checked = Self.workout()
        checked.healthCheckedAt = Self.t0.addingTimeInterval(7200)
        let outcome = await HealthEnrichmentRun.backfill(
            workouts: [checked],
            source: Self.source([("HK-1", 0)]),
            now: Self.later
        )
        #expect(outcome == Outcome())
        #expect(checked.healthWorkoutID == nil)
        #expect(checked.healthCheckedAt == Self.t0.addingTimeInterval(7200))
    }

    @Test func backfillIgnoresUnfinishedAndAlreadyMatchedWorkouts() async {
        let running = Workout(name: "running", startedAt: Self.t0, updatedAt: Self.t0)
        let matched = Self.workout(startOffset: 7200)
        matched.applyHealth(Self.summary("HK-2", startOffset: 7200), checkedAt: Self.t0)
        let outcome = await HealthEnrichmentRun.backfill(
            workouts: [running, matched],
            source: Self.source([("HK-1", 0)]),
            now: Self.later
        )
        #expect(outcome == Outcome())
        #expect(running.healthCheckedAt == nil && running.healthWorkoutID == nil)
        #expect(matched.healthWorkoutID == "HK-2")
    }

    // Fake-only, like `notAuthorizedFromASourceStopsAndStampsNothing`.
    @Test func backfillStopsWhenASourceReportsNotAuthorizedAndStampsNothing() async {
        let a = Self.workout(startOffset: 0)
        let b = Self.workout(startOffset: 7200)
        let outcome = await HealthEnrichmentRun.backfill(
            workouts: [a, b],
            source: FakeHealthSource.failing(.notAuthorized),
            now: Self.later
        )
        #expect(outcome == Outcome(matched: 0, checked: 0, stopped: .notAuthorized))
        #expect(a.healthCheckedAt == nil && b.healthCheckedAt == nil)
    }

    @Test func backfillSkipsAnErroringWorkoutWithoutStampingAndGoesOn() async {
        let a = Self.workout(startOffset: 0)
        let b = Self.workout(startOffset: 7200)
        let source = FlakySource(
            base: Self.source([("HK-1", 0), ("HK-2", 7200)]),
            failSummaryFor: ["HK-1": .failed("boom")]
        )
        let outcome = await HealthEnrichmentRun.backfill(workouts: [a, b], source: source, now: Self.later)
        #expect(outcome == Outcome(matched: 1, checked: 1, stopped: nil))
        #expect(a.healthWorkoutID == nil && a.healthCheckedAt == nil)
        #expect(b.healthWorkoutID == "HK-2")
    }

    @Test func backfillClaimsHoldAcrossOldAndNewWorkouts() async {
        // One Fitness workout; a recent workout already holds it, so the old never-checked one cannot take it.
        let recent = Workout(
            name: "recent",
            startedAt: Self.later.addingTimeInterval(-3600),
            finishedAt: Self.later.addingTimeInterval(-600),
            updatedAt: Self.later
        )
        recent.applyHealth(Self.summary("HK-1"), checkedAt: Self.later)
        let old = Self.workout(startOffset: 0, name: "old")
        let outcome = await HealthEnrichmentRun.backfill(
            workouts: [recent, old],
            source: Self.source([("HK-1", 0)]),
            now: Self.later
        )
        #expect(outcome == Outcome(matched: 0, checked: 1, stopped: nil))
        #expect(old.healthWorkoutID == nil)
        #expect(old.healthCheckedAt == Self.later)
        #expect(recent.healthWorkoutID == "HK-1")
    }

    @Test func backfillClaimsWithinThePassOldestFirst() async {
        let older = Self.workout(startOffset: 0, name: "older")
        let newer = Self.workout(startOffset: 600, name: "newer")
        let outcome = await HealthEnrichmentRun.backfill(
            workouts: [newer, older],
            source: Self.source([("HK-1", 0)]),
            now: Self.later
        )
        #expect(outcome == Outcome(matched: 1, checked: 2, stopped: nil))
        #expect(older.healthWorkoutID == "HK-1")
        #expect(newer.healthWorkoutID == nil)
    }

    @Test func backfillReportsProgress() async {
        let a = Self.workout(startOffset: 0)
        let b = Self.workout(startOffset: 7200)
        var seen: [[Int]] = []
        _ = await HealthEnrichmentRun.backfill(
            workouts: [b, a],
            source: FakeHealthSource(),
            now: Self.later,
            progress: { seen.append([$0, $1]) }
        )
        #expect(seen == [[0, 2], [1, 2], [2, 2]])
    }

    @Test func backfillStopsWhenItsTaskIsCancelled() async {
        let a = Self.workout(startOffset: 0)
        let b = Self.workout(startOffset: 7200)
        let source = Self.source([("HK-1", 0), ("HK-2", 7200)])
        let task = Task { await HealthEnrichmentRun.backfill(workouts: [a, b], source: source, now: Self.later) }
        task.cancel()
        let outcome = await task.value
        #expect(outcome == Outcome())
        #expect(a.healthCheckedAt == nil && b.healthCheckedAt == nil)
    }

    @Test func backfillCandidatesDescriptorReturnsOnlyFinishedUnmatchedUncheckedOldestFirst() throws {
        let context = try makeTestContext()
        let newest = Self.workout(startOffset: 7200, name: "newest")
        let oldest = Self.workout(startOffset: 0, name: "oldest")
        let active = Workout(name: "active", startedAt: Self.t0, updatedAt: Self.t0)
        let checked = Self.workout(startOffset: 3600, name: "checked")
        checked.healthCheckedAt = Self.t0
        let matched = Self.workout(startOffset: 3600, name: "matched")
        matched.healthWorkoutID = "HK-1"
        for workout in [newest, active, oldest, checked, matched] { context.insert(workout) }
        try context.save()
        let names = try context.fetch(HealthEnrichmentRun.backfillCandidatesDescriptor()).map(\.name)
        #expect(names == ["oldest", "newest"])
    }
}

private struct HealthSaveFailed: Error {}
