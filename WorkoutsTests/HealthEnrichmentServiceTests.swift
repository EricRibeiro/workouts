import Foundation
import SwiftData
import Testing
import WorkoutsKit

@testable import Workouts

/// Lets a test hold a source call open until `release()`, so it can act while a pass is in flight.
private actor Gate {
    private var entered = false
    private var released = false
    private(set) var lookups = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        lookups += 1
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters = []
    }

    var hasEntered: Bool { entered }
}

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

/// A source that answers "no workouts" (what HealthKit does for a denied read) until `grant()`, then the wrapped one.
private actor Access {
    private(set) var granted = false
    func grant() { granted = true }
}

private nonisolated struct DeniableSource: HealthSource {
    let access: Access
    let base: FakeHealthSource

    func workouts(in interval: DateInterval) async throws -> [HealthWorkoutCandidate] {
        guard await access.granted else { return [] }
        return try await base.workouts(in: interval)
    }

    func summary(for candidate: HealthWorkoutCandidate) async throws -> HealthWorkoutSummary {
        try await base.summary(for: candidate)
    }
}

@MainActor
struct HealthEnrichmentServiceTests {
    private struct Setup {
        let service: HealthEnrichmentService
        let settings: SettingsStore
        let context: ModelContext
        let workout: Workout
        let gate: Gate
    }

    /// A service over a gated source holding one Fitness workout that matches the one finished workout, opted in.
    private func makeSetup(followUpDelay: Duration = .seconds(120), endedAgo: TimeInterval = 600) throws -> Setup {
        let end = Date.now.addingTimeInterval(-endedAgo)
        let start = end.addingTimeInterval(-3000)
        let candidate = HealthWorkoutCandidate(id: "HK-1", kind: .functionalStrength, start: start, end: end)
        let summary = HealthWorkoutSummary(
            healthWorkoutID: "HK-1",
            start: start,
            end: end,
            activeEnergyKcal: 300,
            totalEnergyKcal: 400,
            avgHeartRate: 120,
            maxHeartRate: 160,
            heartRateSeries: []
        )
        let gate = Gate()
        let source = GatedSource(gate: gate, base: FakeHealthSource(candidates: [candidate], summaries: [summary]))
        let settings = SettingsStore(backend: InMemoryBackend())
        settings.healthEnrichmentEnabled = true
        let context = ModelContext(try ModelContainer.workouts(inMemory: true, cloudKit: false))
        let workout = Workout(name: "Push", startedAt: start, finishedAt: end, updatedAt: start)
        context.insert(workout)
        try context.save()
        return Setup(
            service: HealthEnrichmentService(source: source, settings: settings, followUpDelay: followUpDelay),
            settings: settings,
            context: context,
            workout: workout,
            gate: gate
        )
    }

    private func waitUntilInFlight(_ gate: Gate) async {
        for _ in 0..<500 {
            if await gate.hasEntered { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aPassAppliesFitnessDataWhenOptedIn() async throws {
        let setup = try makeSetup()
        await setup.gate.release()
        await setup.service.refresh(context: setup.context)
        #expect(setup.workout.healthWorkoutID == "HK-1")
        #expect(setup.workout.activeEnergyKcal == 300)
    }

    @Test func becomingActiveBackfillsAnOldWorkoutButARoutineRefreshDoesNot() async throws {
        let setup = try makeSetup(endedAgo: 30 * 86400)
        await setup.gate.release()
        await setup.service.refresh(context: setup.context)
        #expect(setup.workout.healthWorkoutID == nil && setup.workout.healthCheckedAt == nil)

        await setup.service.appBecameActive(context: setup.context)
        #expect(setup.workout.healthWorkoutID == "HK-1")
        #expect(setup.workout.activeEnergyKcal == 300)
    }

    @Test func optingInAgainLooksAtWorkoutsAnEarlierEmptyPassStamped() async throws {
        // An earlier pass ran while access was denied (HealthKit answered "no data") and stamped the workout unmatched.
        let setup = try makeSetup(endedAgo: 30 * 86400)
        setup.workout.applyHealth(nil, checkedAt: .now.addingTimeInterval(-86400))
        await setup.gate.release()

        // Premise: the ordinary foreground pass never looks at a stamped workout again.
        await setup.service.appBecameActive(context: setup.context)
        #expect(setup.workout.healthWorkoutID == nil)

        // The person turns the toggle on again: the stamp is cleared and the source, which now has the match, is asked.
        await setup.service.requestAuthorization(context: setup.context)
        #expect(setup.workout.healthWorkoutID == "HK-1")
        #expect(setup.workout.activeEnergyKcal == 300)
    }

    @Test func optingInKeepsExistingMatches() async throws {
        let setup = try makeSetup(endedAgo: 30 * 86400)
        let matchedAt = Date.now.addingTimeInterval(-86400)
        setup.workout.applyHealth(
            HealthWorkoutSummary(
                healthWorkoutID: "HK-OLD",
                start: setup.workout.startedAt,
                end: setup.workout.finishedAt ?? .now,
                activeEnergyKcal: 111
            ),
            checkedAt: matchedAt
        )
        await setup.gate.release()
        await setup.service.requestAuthorization(context: setup.context)
        #expect(setup.workout.healthWorkoutID == "HK-OLD")
        #expect(setup.workout.activeEnergyKcal == 111)
        #expect(setup.workout.healthCheckedAt == matchedAt)
    }

    @Test func refreshNowRechecksAWorkoutTheRoutinePassThrottles() async throws {
        let setup = try makeSetup()
        // Checked a minute ago, no match then: inside the 15-minute throttle.
        setup.workout.applyHealth(nil, checkedAt: .now.addingTimeInterval(-60))
        await setup.gate.release()

        await setup.service.refresh(context: setup.context)
        #expect(setup.workout.healthWorkoutID == nil)

        await setup.service.refreshNow(context: setup.context)
        #expect(setup.workout.healthWorkoutID == "HK-1")
        #expect(setup.workout.activeEnergyKcal == 300)
    }

    @Test func pullToRefreshFindsAnOldWorkoutAfterAccessIsGrantedLater() async throws {
        let end = Date.now.addingTimeInterval(-30 * 86400)
        let start = end.addingTimeInterval(-3000)
        let candidate = HealthWorkoutCandidate(id: "HK-1", kind: .functionalStrength, start: start, end: end)
        let summary = HealthWorkoutSummary(
            healthWorkoutID: "HK-1",
            start: start,
            end: end,
            activeEnergyKcal: 300,
            totalEnergyKcal: 400
        )
        let access = Access()
        let base = FakeHealthSource(candidates: [candidate], summaries: [summary])
        let source = DeniableSource(access: access, base: base)
        let settings = SettingsStore(backend: InMemoryBackend())
        settings.healthEnrichmentEnabled = true
        let context = ModelContext(try ModelContainer.workouts(inMemory: true, cloudKit: false))
        let workout = Workout(name: "Push", startedAt: start, finishedAt: end, updatedAt: start)
        context.insert(workout)
        try context.save()
        let service = HealthEnrichmentService(source: source, settings: settings)

        // Opt-in while denied: the empty answer stamps the old workout unmatched.
        await service.requestAuthorization(context: context)
        #expect(workout.healthWorkoutID == nil && workout.healthCheckedAt != nil)

        // Access is granted later in the Health app. The routine pass (7 days) and the foreground backfill (unchecked only)
        // both leave the stamped workout alone.
        await access.grant()
        await service.refresh(context: context)
        await service.appBecameActive(context: context)
        #expect(workout.healthWorkoutID == nil)

        // Pull to refresh is the explicit "check again".
        await service.refreshNow(context: context)
        #expect(workout.healthWorkoutID == "HK-1")
        #expect(workout.activeEnergyKcal == 300)
    }

    @Test func refreshNowAlsoBackfillsOldWorkouts() async throws {
        let setup = try makeSetup(endedAgo: 30 * 86400)
        await setup.gate.release()
        await setup.service.refreshNow(context: setup.context)
        #expect(setup.workout.healthWorkoutID == "HK-1")
    }

    @Test func refreshNowJoinsARunningPassAndReturnsOnlyWhenItIsDone() async throws {
        let setup = try makeSetup()
        let routine = Task { await setup.service.refresh(context: setup.context) }
        await waitUntilInFlight(setup.gate)
        var finished = false
        let forced = Task {
            await setup.service.refreshNow(context: setup.context)
            finished = true
        }
        await Task.yield()
        #expect(!finished)  // the source is still held open
        await setup.gate.release()
        await forced.value
        await routine.value
        #expect(setup.workout.healthWorkoutID == "HK-1")
    }

    @Test func refreshNowStartedAloneStaysSuspendedWhileTheLookupRuns() async throws {
        // The pull-to-refresh spinner lasts exactly as long as `refreshNow` is suspended, so a lone call must not return
        // while the source is still answering, and must return, with the workout enriched, once it has.
        let setup = try makeSetup()
        var finished = false
        let pull = Task {
            await setup.service.refreshNow(context: setup.context)
            finished = true
        }
        await waitUntilInFlight(setup.gate)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!finished)
        #expect(setup.workout.healthWorkoutID == nil)

        await setup.gate.release()
        await pull.value
        #expect(finished)
        #expect(setup.workout.healthWorkoutID == "HK-1")
        #expect(setup.workout.activeEnergyKcal == 300)
    }

    @Test func overlappingRefreshNowCallsShareOnePassAndBothWaitForIt() async throws {
        let setup = try makeSetup()
        var finished = (first: false, second: false)
        let first = Task {
            await setup.service.refreshNow(context: setup.context)
            finished.first = true
        }
        await waitUntilInFlight(setup.gate)
        let second = Task {
            await setup.service.refreshNow(context: setup.context)
            finished.second = true
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!finished.first && !finished.second)
        // The second call joined: only the first call's lookup is open, no concurrent second one.
        #expect(await setup.gate.lookups == 1)

        await setup.gate.release()
        await first.value
        await second.value
        #expect(finished.first && finished.second)
        #expect(setup.workout.healthWorkoutID == "HK-1")
        // At most the one extra round the joiner asks for (its fetch may predate the request); never a third.
        #expect(await setup.gate.lookups <= 2)
    }

    @Test func refreshNowAcrossTurnOffReturnsAndNothingIsWrittenAfterwards() async throws {
        let setup = try makeSetup()
        let routine = Task { await setup.service.refresh(context: setup.context) }
        await waitUntilInFlight(setup.gate)
        let pull = Task { await setup.service.refreshNow(context: setup.context) }  // joins and queues another round
        let off = Task { try await setup.service.turnOff(remove: true, context: setup.context) }
        await Task.yield()
        #expect(!setup.settings.healthEnrichmentEnabled)

        await setup.gate.release()
        try await off.value
        await pull.value
        await routine.value
        let lookups = await setup.gate.lookups

        // The queued round was dropped (setting off, nothing re-queued), and the removal was not undone.
        try await Task.sleep(for: .milliseconds(200))
        #expect(await setup.gate.lookups == lookups)
        #expect(lookups == 1)
        #expect(setup.workout.healthWorkoutID == nil)
        #expect(setup.workout.healthCheckedAt == nil)
        #expect(setup.workout.activeEnergyKcal == nil)
    }

    @Test func refreshNowStartedAfterTurnOffDoesNothing() async throws {
        let setup = try makeSetup()
        await setup.gate.release()
        try await setup.service.turnOff(remove: true, context: setup.context)
        await setup.service.refreshNow(context: setup.context)
        #expect(await setup.gate.lookups == 0)
        #expect(setup.workout.healthWorkoutID == nil && setup.workout.healthCheckedAt == nil)
    }

    @Test func refreshNowDoesNothingWhileOptedOut() async throws {
        let setup = try makeSetup()
        setup.settings.healthEnrichmentEnabled = false
        await setup.gate.release()
        await setup.service.refreshNow(context: setup.context)
        #expect(setup.workout.healthWorkoutID == nil && setup.workout.healthCheckedAt == nil)
    }

    @Test func backfillIsANoOpWhileOptedOut() async throws {
        let setup = try makeSetup(endedAgo: 30 * 86400)
        setup.settings.healthEnrichmentEnabled = false
        await setup.gate.release()
        await setup.service.backfill(context: setup.context)
        await setup.service.appBecameActive(context: setup.context)
        #expect(setup.workout.healthWorkoutID == nil && setup.workout.healthCheckedAt == nil)
    }

    @Test func nothingRunsWhileOptedOut() async throws {
        let setup = try makeSetup()
        setup.settings.healthEnrichmentEnabled = false
        await setup.gate.release()
        await setup.service.refresh(context: setup.context)
        #expect(setup.workout.healthWorkoutID == nil && setup.workout.healthCheckedAt == nil)
    }

    @Test func removeWaitsForAPassInFlightSoItCannotReapplyData() async throws {
        let setup = try makeSetup()
        let refresh = Task { await setup.service.refresh(context: setup.context) }
        await waitUntilInFlight(setup.gate)

        // The pass is suspended inside the source. Turn off with Remove, then let the pass finish.
        let off = Task { try await setup.service.turnOff(remove: true, context: setup.context) }
        await Task.yield()
        #expect(!setup.settings.healthEnrichmentEnabled)
        await setup.gate.release()
        try await off.value
        await refresh.value

        #expect(setup.workout.healthWorkoutID == nil)
        #expect(setup.workout.healthCheckedAt == nil)
        #expect(setup.workout.activeEnergyKcal == nil)
    }

    @Test func keepLeavesWhatTheInFlightPassApplied() async throws {
        let setup = try makeSetup()
        let refresh = Task { await setup.service.refresh(context: setup.context) }
        await waitUntilInFlight(setup.gate)
        let off = Task { try await setup.service.turnOff(remove: false, context: setup.context) }
        await setup.gate.release()
        try await off.value
        await refresh.value
        #expect(!setup.settings.healthEnrichmentEnabled)
        #expect(setup.workout.healthWorkoutID == "HK-1")
    }

    @Test func turnOffCancelsTheFollowUp() async throws {
        let setup = try makeSetup(followUpDelay: .milliseconds(200))
        await setup.gate.release()
        setup.service.workoutFinished(context: setup.context)
        // The immediate lookup applies the data; clear it, then make sure the follow-up does not bring it back.
        await waitUntilInFlight(setup.gate)
        try await setup.service.turnOff(remove: true, context: setup.context)
        try await Task.sleep(for: .milliseconds(500))
        #expect(setup.workout.healthWorkoutID == nil)
        #expect(setup.workout.healthCheckedAt == nil)
    }
}
