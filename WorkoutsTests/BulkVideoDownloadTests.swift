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
}
