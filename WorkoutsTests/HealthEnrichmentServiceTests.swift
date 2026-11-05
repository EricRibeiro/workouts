import Foundation
import SwiftData
import Testing
import WorkoutsKit

@testable import Workouts

/// Lets a test hold a source call open until `release()`, so it can act while a pass is in flight.
private actor Gate {
    private var entered = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
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
