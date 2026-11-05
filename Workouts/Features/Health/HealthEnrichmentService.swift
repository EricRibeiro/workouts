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
    /// Set when a backfill was requested while the loop ran; it follows the refresh in the next round.
    @ObservationIgnored private var queuedBackfill = false
    @ObservationIgnored private var followUp: Task<Void, Never>?

    /// While a backfill runs, how many of the workouts it will look at are done; nil otherwise. Settings shows it.
    private(set) var backfillProgress: (done: Int, total: Int)?
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
        await request(context: context, recheckAfter: recheckAfter, backfill: false)
    }

    /// The app came to the foreground: the routine refresh, then the backfill, in one serialised round. Backfill only
    /// touches workouts never checked, so once everything is stamped this costs an in-memory scan; and a grant given
    /// later (Health settings) still reaches old workouts that an earlier denied pass left unstamped.
    func appBecameActive(context: ModelContext) async {
        await request(context: context, recheckAfter: Self.defaultRecheck, backfill: true)
    }

    /// One lookup over every finished workout that was never checked, however old (PLAN 7.1b g): imported history and
    /// workouts from before the person opted in, which the routine pass gave up on. Each workout is stamped, so it is
    /// looked up once. Joins the refresh loop, so it never overlaps a refresh and `turnOff` waits for it.
    func backfill(context: ModelContext) async {
        await request(context: context, recheckAfter: nil, backfill: true)
    }

    /// The one entry to the serialised loop. `recheckAfter` nil means no routine pass this time. A call while the loop
    /// runs only queues what it asked for: the running loop goes around again, since its fetch may predate the request.
    private func request(context: ModelContext, recheckAfter: TimeInterval?, backfill: Bool) async {
        guard isActive, let source else { return }
        if runningRefresh != nil {
            if let recheckAfter { queuedRecheck = min(queuedRecheck ?? recheckAfter, recheckAfter) }
            if backfill { queuedBackfill = true }
            return
        }
        // A task, not an inline loop, so `turnOff` can await it. It runs on the main actor like the service.
        let task = Task { [self] in
            var recheck = recheckAfter
            var wantsBackfill = backfill
            while isActive, recheck != nil || wantsBackfill {
                let round = (recheck: recheck, backfill: wantsBackfill)
                queuedRecheck = nil
                queuedBackfill = false
                if let interval = round.recheck {
                    await pass(context: context, source: source, recheckAfter: interval)
                }
                if round.backfill, isActive {
                    await backfillPass(context: context, source: source)
                }
                recheck = queuedRecheck
                wantsBackfill = queuedBackfill
            }
            queuedRecheck = nil
            queuedBackfill = false
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

    private func backfillPass(context: ModelContext, source: any HealthSource) async {
        defer { backfillProgress = nil }
        do {
            let workouts = try context.fetch(HealthEnrichmentRun.allFinishedDescriptor())
            let outcome = await HealthEnrichmentRun.backfill(
                workouts: workouts,
                source: source,
                now: .now,
                progress: { [weak self] done, total in
                    self?.backfillProgress = total > 0 && done < total ? (done, total) : nil
                    // A long backfill saves as it goes, so quitting the app midway keeps what was found.
                    if done > 0, done.isMultiple(of: 25), context.hasChanges {
                        do { try context.save() } catch {
                            self?.logger.error("Fitness backfill save failed: \(error.localizedDescription)")
                        }
                    }
                }
            )
            if context.hasChanges { try context.save() }
            logger.info("Fitness backfill matched \(outcome.matched) of \(outcome.checked) checked workouts")
        } catch {
            logger.error("Fitness backfill failed: \(error.localizedDescription)")
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
        // Health never reports a denied read, it answers "no data", so an earlier pass (or a previous opt-in) may have
        // stamped workouts as unmatched. Each opt-in looks at them afresh; matches are kept.
        do { try HealthEnrichmentRun.resetUnmatched(context: context) } catch {
            logger.error("Fitness reset failed: \(error.localizedDescription)")
        }
        // The normal refresh first, then the one-time backfill of older workouts, in one serialised round.
        await request(context: context, recheckAfter: Self.defaultRecheck, backfill: true)
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
        queuedBackfill = false
        // Cancelling lets a long backfill stop at its next workout (the kit checks); what it found so far is kept and
        // saved before this resumes.
        runningRefresh?.cancel()
        await runningRefresh?.value
        if remove { try HealthEnrichmentRun.clearAll(context: context) }
    }
}
