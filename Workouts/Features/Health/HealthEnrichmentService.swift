//
//  HealthEnrichmentService.swift
//  Workouts
//

import Foundation
import OSLog
import Observation
import SwiftData
import WorkoutsKit

/// Runs the Apple Fitness enrichment (`HealthEnrichmentRun`) when the app asks: when it becomes active, right after a
/// workout finishes, and once more two minutes later (JC66). One instance lives for the app, injected through the
/// environment next to the other services.
///
/// Opt-in: nothing runs, and Health is never asked, until Settings turns `healthEnrichmentEnabled` on.
///
/// The source is chosen once, at launch (`atLaunch`). Nil means "no Health here" (iPad, a restricted device, UI tests that
/// did not ask for a fixture): every call is then a no-op and Settings hides its Apple Fitness section.
@Observable
@MainActor
final class HealthEnrichmentService {
    /// Where Fitness data comes from; nil when Health is not available.
    let source: (any HealthSource)?

    /// The opt-in lives here; read at each call, so a toggle in Settings takes effect at once.
    private let settings: SettingsStore

    /// How long a lookup that found no match is left alone (the kit's default, JC66).
    private static let defaultRecheck: TimeInterval = 15 * 60
    /// The follow-up lookup must not be blocked by the stamp the first lookup left, so it re-checks anything older than
    /// this (JC66: the Watch workout usually ends just after ours).
    private static let followUpRecheck: TimeInterval = 60

    @ObservationIgnored private let followUpDelay: Duration
    /// The pass loop in flight, if any. Stored so `turnOff` can wait for it: a pass applies results after each `await`,
    /// so clearing the data while one runs would be undone.
    @ObservationIgnored private var runningRefresh: Task<Void, Never>?
    /// Set when a refresh was requested while one ran; the running one goes around again, since its fetch may predate the
    /// request. Holds the shortest re-check interval asked for.
    @ObservationIgnored private var queuedRecheck: TimeInterval?
    @ObservationIgnored private var followUp: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "com.ericribeiro.Workouts", category: "Health")

    init(source: (any HealthSource)?, settings: SettingsStore, followUpDelay: Duration = .seconds(120)) {
        self.source = source
        self.settings = settings
        self.followUpDelay = followUpDelay
    }

    /// The service for this launch. DEBUG `-healthFixture <name>` wins; UI tests (`-uiTesting`) otherwise never touch real
    /// Health; else HealthKit where the device has it.
    static func atLaunch(settings: SettingsStore, arguments: [String] = ProcessInfo.processInfo.arguments)
        -> HealthEnrichmentService
    {
        #if DEBUG
            if let fixture = HealthFixture.requested(arguments) {
                return HealthEnrichmentService(source: fixture.anyWorkoutSource, settings: settings)
            }
            if arguments.contains("-uiTesting") {
                return HealthEnrichmentService(source: nil, settings: settings)
            }
        #endif
        return HealthEnrichmentService(
            source: HealthKitSource.isAvailable ? HealthKitSource() : nil,
            settings: settings
        )
    }

    var isAvailable: Bool { source != nil }

    /// Available and opted in.
    private var isActive: Bool { source != nil && settings.healthEnrichmentEnabled }

    /// One lookup pass over the recent finished workouts, saved when it changed anything. A call while a pass runs does not
    /// overlap it: the running pass goes around once more when it finishes.
    func refresh(context: ModelContext) async {
        await refresh(context: context, recheckAfter: Self.defaultRecheck)
    }

    private func refresh(context: ModelContext, recheckAfter: TimeInterval) async {
        guard isActive, let source else { return }
        if runningRefresh != nil {
            queuedRecheck = min(queuedRecheck ?? recheckAfter, recheckAfter)
            return
        }
        // A task, not an inline loop, so `turnOff` can await it. It runs on the main actor like the service.
        let task = Task { [self] in
            var recheck = recheckAfter
            repeat {
                queuedRecheck = nil
                await pass(context: context, source: source, recheckAfter: recheck)
                recheck = queuedRecheck ?? recheck
            } while queuedRecheck != nil && isActive
            queuedRecheck = nil
            runningRefresh = nil
        }
        runningRefresh = task
        await task.value
    }

    private func pass(context: ModelContext, source: any HealthSource, recheckAfter: TimeInterval) async {
        let now = Date.now
        do {
            let workouts = try context.fetch(HealthEnrichmentRun.recentFinishedDescriptor(now: now))
            let outcome = await HealthEnrichmentRun.run(
                workouts: workouts,
                source: source,
                now: now,
                recheckAfter: recheckAfter
            )
            if context.hasChanges { try context.save() }
            if outcome.matched > 0 {
                logger.info("Fitness matched \(outcome.matched) of \(outcome.checked) checked workouts")
            }
        } catch {
            logger.error("Fitness lookup failed: \(error.localizedDescription)")
        }
    }

    /// Shows the Health read sheet (HealthKit only; a fixture has nothing to ask), then looks up what is waiting. Called
    /// when the person turns the Settings toggle on, so `healthEnrichmentEnabled` is already true.
    func requestAuthorization(context: ModelContext) async {
        guard source != nil else { return }
        if let healthKit = source as? HealthKitSource {
            do {
                try await healthKit.requestReadAuthorization()
            } catch {
                logger.error("Health authorization failed: \(error.localizedDescription)")
                return
            }
        }
        await refresh(context: context)
    }

    /// A workout just finished: look now, and once more after `followUpDelay`, when the Watch workout has ended too. A
    /// later finish replaces a pending follow-up.
    func workoutFinished(context: ModelContext) {
        guard isActive else { return }
        followUp?.cancel()
        let delay = followUpDelay
        Task { await refresh(context: context) }
        followUp = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            await self?.refresh(context: context, recheckAfter: Self.followUpRecheck)
        }
    }

    /// The Settings toggle going off. Order matters: the setting goes off first (a pass in flight stops going around and
    /// no new one starts), the follow-up is cancelled, and a pass already in flight is awaited, since it applies results
    /// after each `await` and would put back what a removal just cleared. Only then, when `remove` is true, is the
    /// Fitness data cleared.
    func turnOff(remove: Bool, context: ModelContext) async throws {
        settings.healthEnrichmentEnabled = false
        followUp?.cancel()
        followUp = nil
        queuedRecheck = nil
        await runningRefresh?.value
        if remove { try HealthEnrichmentRun.clearAll(context: context) }
    }
}
