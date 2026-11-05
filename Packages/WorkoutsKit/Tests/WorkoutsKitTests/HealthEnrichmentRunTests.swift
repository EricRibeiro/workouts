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

@Suite struct HealthEnrichmentRunTests {
    private typealias Outcome = HealthEnrichmentRun.Outcome

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static let now = t0.addingTimeInterval(86400)

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer.workouts(inMemory: true, cloudKit: false))
    }

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

    @Test func notAuthorizedStopsAndStampsNothing() async {
        let a = Self.workout(startOffset: 0)
        let b = Self.workout(startOffset: 7200)
        let outcome = await HealthEnrichmentRun.run(
            workouts: [a, b],
            source: FakeHealthSource.failing(.notAuthorized),
            now: Self.now
        )
        #expect(outcome == Outcome(matched: 0, checked: 0, stopped: .notAuthorized))
        #expect(outcome.stoppedForAuthorization)
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
        let context = try makeContext()
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
}
