import Foundation
import Testing
import WorkoutsKit

@testable import Workouts

/// Every fetch throws until `goOnline()`, like a Wi-Fi-only fetch on cellular; afterwards each id has a video.
private nonisolated final class FlakyMediaSource: MediaSource, @unchecked Sendable {
    struct Offline: Error {}

    private let lock = NSLock()
    private let directory: URL
    private var online: Bool

    init(directory: URL, online: Bool) {
        self.directory = directory
        self.online = online
    }

    func goOnline() { lock.withLock { online = true } }

    func fetchVideo(sourceId: String, scheme: MediaScheme) async throws -> URL? {
        guard lock.withLock({ online }) else { throw Offline() }
        let file = directory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data(repeating: 1, count: 8).write(to: file)
        return file
    }
}

/// Every fetch waits for `release()`, like a slow network, so a test can look at the controller mid-run. Waiting does not
/// observe cancellation (a cancelled prefetch still finishes the file it is fetching).
private nonisolated final class HeldMediaSource: MediaSource, @unchecked Sendable {
    private let lock = NSLock()
    private let directory: URL
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(directory: URL) { self.directory = directory }

    func release() {
        let toResume = lock.withLock {
            released = true
            defer { waiters = [] }
            return waiters
        }
        toResume.forEach { $0.resume() }
    }

    func fetchVideo(sourceId: String, scheme: MediaScheme) async throws -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock {
                if !released { waiters.append(continuation) }
                return released
            }
            if resumeNow { continuation.resume() }
        }
        let file = directory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data(repeating: 1, count: 8).write(to: file)
        return file
    }
}

@MainActor
struct BulkVideoDownloadTests {
    private func makeStore(online: Bool) throws -> (MediaStore, FlakyMediaSource, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "BulkVideoDownloadTests-\(UUID().uuidString)")
        let scratch = root.appending(path: "source")
        let cache = root.appending(path: "cache")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let source = FlakyMediaSource(directory: scratch, online: online)
        return (MediaStore(source: source, bundle: .main, cacheDirectory: cache), source, root)
    }

    @Test func aRunThatFailedDoesNotCountTheFailuresAsDoneAndTheNextStartRetriesThem() async throws {
        let (store, source, root) = try makeStore(online: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let download = BulkVideoDownload(store: store)
        let ids = ["a", "b", "c"]

        await download.start(sourceIDs: ids, scheme: .light)?.value
        #expect(download.failedSourceIDs == ids)
        #expect(!download.isRunning)
        #expect(download.progress == nil)
        for id in ids { #expect(store.cachedVideoURL(for: id, scheme: .light) == nil) }

        // Back on Wi-Fi: the next start fetches what the first could not.
        source.goOnline()
        await download.start(sourceIDs: ids, scheme: .light)?.value
        #expect(download.failedSourceIDs.isEmpty)
        for id in ids { #expect(store.cachedVideoURL(for: id, scheme: .light) != nil) }
    }

    @Test func startWhileRunningReturnsTheRunningTask() async throws {
        let (store, _, root) = try makeStore(online: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let download = BulkVideoDownload(store: store)
        let first = download.start(sourceIDs: ["a"], scheme: .light)
        #expect(download.isRunning)
        let second = download.start(sourceIDs: ["a"], scheme: .light)
        #expect(first == second)
        await first?.value
        #expect(!download.isRunning)
    }

    @Test func progressStartsAtTheCachedCountAndAFullyCachedLibraryShowsNoBar() async throws {
        let (store, _, root) = try makeStore(online: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = ["a", "b", "c", "d"]
        _ = try await store.video(for: "a", scheme: .light)
        _ = try await store.video(for: "b", scheme: .light)
        let download = BulkVideoDownload(store: store)

        // The bar opens at 2 of 4 (what is on disk), not at 0.
        let running = download.start(sourceIDs: ids, scheme: .light)
        #expect(download.progress?.done == 2)
        #expect(download.progress?.total == 4)
        await running?.value
        #expect(download.progress == nil)

        // Everything is cached now: starting again (Settings reopened) shows nothing and runs nothing.
        #expect(download.start(sourceIDs: ids, scheme: .light) == nil)
        #expect(download.progress == nil)
        #expect(!download.isRunning)
    }

    private func makeHeldStore() throws -> (MediaStore, HeldMediaSource, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "BulkVideoDownloadTests-\(UUID().uuidString)")
        let scratch = root.appending(path: "source")
        let cache = root.appending(path: "cache")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let source = HeldMediaSource(directory: scratch)
        return (MediaStore(source: source, bundle: .main, cacheDirectory: cache), source, root)
    }

    @Test func aSecondStartAfterACompletedRunOpensAtWhatIsCachedAndRunsAgain() async throws {
        let (store, source, root) = try makeHeldStore()
        defer { try? FileManager.default.removeItem(at: root) }
        source.release()
        let download = BulkVideoDownload(store: store)

        let first = download.start(sourceIDs: ["a", "b"], scheme: .light)
        await first?.value
        #expect(!download.isRunning)
        #expect(download.progress == nil)

        // The library grew: the second start opens at the 2 cached of 3, running, before anything is awaited.
        let second = download.start(sourceIDs: ["a", "b", "c"], scheme: .light)
        #expect(second != nil)
        #expect(second != first)
        #expect(download.isRunning)
        #expect(download.progress?.done == 2)
        #expect(download.progress?.total == 3)
        await second?.value
        #expect(!download.isRunning)
        #expect(download.progress == nil)
        #expect(download.failedSourceIDs.isEmpty)
        #expect(store.cachedVideoURL(for: "c", scheme: .light) != nil)
    }

    @Test func aSecondStartAfterAFailedRunOpensRunningAtZeroAndTheFailuresStopCounting() async throws {
        let (store, source, root) = try makeStore(online: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let download = BulkVideoDownload(store: store)
        let ids = ["a", "b", "c"]
        await download.start(sourceIDs: ids, scheme: .light)?.value
        #expect(download.failedSourceIDs == ids)

        source.goOnline()
        let second = download.start(sourceIDs: ids, scheme: .light)
        #expect(second != nil)
        #expect(download.isRunning)
        #expect(download.progress?.done == 0)
        #expect(download.progress?.total == 3)
        await second?.value
        #expect(download.failedSourceIDs.isEmpty)
        #expect(!download.isRunning)
        #expect(download.progress == nil)
    }

    @Test func aSecondStartAfterACancelledRunStartsFreshAndTheCancelledOneDoesNotTouchIt() async throws {
        let (store, source, root) = try makeHeldStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let download = BulkVideoDownload(store: store)
        let ids = ["a", "b", "c"]

        let first = download.start(sourceIDs: ids, scheme: .light)
        #expect(download.isRunning)
        let cancelled = download.cancel()
        #expect(cancelled == first)
        #expect(!download.isRunning)
        #expect(download.progress == nil)

        // Right after the second start: a new task, running, the bar at 0 of 3.
        let second = download.start(sourceIDs: ids, scheme: .light)
        #expect(second != nil)
        #expect(second != first)
        #expect(download.isRunning)
        #expect(download.progress?.done == 0)
        #expect(download.progress?.total == 3)

        // The cancelled run finishes its in-flight files; it must not clear or move the second run's state.
        source.release()
        await first?.value
        await Task.yield()
        await second?.value
        #expect(!download.isRunning)
        #expect(download.progress == nil)
        #expect(download.failedSourceIDs.isEmpty)
        for id in ids { #expect(store.cachedVideoURL(for: id, scheme: .light) != nil) }
    }
}
