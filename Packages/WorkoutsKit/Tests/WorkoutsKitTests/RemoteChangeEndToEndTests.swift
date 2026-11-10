import CoreData
import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

/// The remote-change chain with nothing hand-called: a save through a second container on the same on-disk store posts
/// `NSPersistentStoreRemoteChange` (the CloudKit mirror merges the same way) → ``RemoteChangeObserver`` →
/// ``ForeignHistoryCheck`` (author filter) → ``ActiveWorkoutEngine/reloadAfterRemoteChange()``.
@Suite struct RemoteChangeEndToEndTests {
    private static let localAuthor = "app"
    private static let mirrorAuthor = "NSCloudKitMirroringDelegate.import"
    private let now = TestSupport.referenceDate
    private let debounce = Duration.milliseconds(100)

    /// Two containers (A = this app, B = "the mirror") on one temp store, an engine on A and the observer on A.
    @MainActor
    private final class Rig {
        let directory: URL
        let appContainer: ModelContainer
        let mirrorContext: ModelContext
        let engine: ActiveWorkoutEngine
        let clock = ManualClock()
        let signal = CallSignal()
        var observer: RemoteChangeObserver!
        var asked = 0
        var handlerCalls = 0

        init(now: Date, debounce: Duration) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "remote-change-\(UUID().uuidString)"
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("store.sqlite")
            appContainer = try .workouts(at: url)
            appContainer.mainContext.author = RemoteChangeEndToEndTests.localAuthor
            mirrorContext = ModelContext(try .workouts(at: url))
            mirrorContext.author = RemoteChangeEndToEndTests.mirrorAuthor
            engine = try ActiveWorkoutEngine(
                context: appContainer.mainContext,
                store: ExerciseStore(catalog: try LibraryFixture.catalog(), custom: []),
                settings: SettingsStore(backend: InMemoryBackend()),
                now: { now }
            )
            let history = ForeignHistoryCheck(
                context: appContainer.mainContext,
                localAuthor: RemoteChangeEndToEndTests.localAuthor
            )
            observer = RemoteChangeObserver(
                debounce: debounce,
                clock: clock,
                shouldFire: { [unowned self] in
                    asked += 1
                    return history.hasForeignTransactions()
                }
            ) { [unowned self] in
                handlerCalls += 1
                do { try engine.reloadAfterRemoteChange() } catch { Issue.record(error) }
                signal.fire()
            }
            observer.start()
        }

        deinit {
            let directory = directory
            try? FileManager.default.removeItem(at: directory)
        }

        /// Waits for the save's notification, runs out the debounce and waits until `shouldFire` has answered.
        func settleDebounce(_ debounce: Duration) async throws {
            let before = asked
            #expect(
                try await eventually(timeout: .seconds(10)) { observer.scheduleCount >= 1 },
                "no remote-change notification"
            )
            #expect(try await eventually(timeout: .seconds(10)) { clock.sleeperCount == 1 })
            clock.advance(by: debounce)
            #expect(try await eventually(timeout: .seconds(10)) { asked > before })
            // A second notification of the same save re-arms the wait; run that one out too.
            for _ in 0..<20 { await Task.yield() }
            while clock.sleeperCount > 0 {
                clock.advance(by: debounce)
                for _ in 0..<20 { await Task.yield() }
            }
        }
    }

    @MainActor
    @Test func mirrorSaveReachesTheEngineThroughTheObserver() async throws {
        let rig = try Rig(now: now, debounce: debounce)
        #expect(rig.engine.workout == nil)
        let remote = Workout(name: "Elsewhere", startedAt: now.addingTimeInterval(-600))
        remote.updatedAt = now
        rig.mirrorContext.insert(remote)
        try rig.mirrorContext.save()

        try await rig.settleDebounce(debounce)
        #expect(rig.handlerCalls == 1, "a foreign save must fire the handler exactly once")
        #expect(rig.engine.workout?.id == remote.id)
        rig.observer.stop()
    }

    @MainActor
    @Test func theAppsOwnSaveDoesNotFireTheHandler() async throws {
        let rig = try Rig(now: now, debounce: debounce)
        try rig.engine.startEmpty()

        try await rig.settleDebounce(debounce)
        #expect(rig.asked >= 1, "the notification never reached the author filter")
        #expect(rig.handlerCalls == 0, "the app's own save must be filtered out")
        rig.observer.stop()
    }

    @MainActor
    @Test func aRecentRemoteWorkoutIsNeverSettledAfterTheReload() async throws {
        let rig = try Rig(now: now, debounce: debounce)
        // Recent and empty: only the 6 h rule keeps it from being deleted as "nothing logged".
        let recent = Workout(name: "Recent", startedAt: now.addingTimeInterval(-3600))
        recent.updatedAt = now.addingTimeInterval(-600)
        // Stale and empty: proves the settle path is live in this run.
        let stale = Workout(name: "Stale", startedAt: now.addingTimeInterval(-30 * 3600))
        stale.updatedAt = now.addingTimeInterval(-30 * 3600)
        rig.mirrorContext.insert(recent)
        rig.mirrorContext.insert(stale)
        try rig.mirrorContext.save()

        try await rig.settleDebounce(debounce)
        #expect(rig.handlerCalls == 1)
        #expect(rig.engine.workout?.id == recent.id)
        let remaining = try rig.appContainer.mainContext.fetch(FetchDescriptor<Workout>())
        #expect(remaining.map(\.id) == [recent.id], "the stale row should be settled, the recent one kept")
        #expect(remaining.first?.finishedAt == nil, "a recent remote workout must stay in progress")
        rig.observer.stop()
    }

    @MainActor
    @Test func foreignHistoryCheckSeesOnlyTransactionsSinceTheLastCall() throws {
        let rig = try Rig(now: now, debounce: debounce)
        rig.observer.stop()
        let check = ForeignHistoryCheck(context: rig.appContainer.mainContext, localAuthor: Self.localAuthor)
        try rig.engine.startEmpty()
        #expect(!check.hasForeignTransactions())
        rig.mirrorContext.insert(Workout(name: "Elsewhere", startedAt: now))
        try rig.mirrorContext.save()
        #expect(check.hasForeignTransactions())
        #expect(!check.hasForeignTransactions(), "the same transactions must not be reported twice")
    }
}
