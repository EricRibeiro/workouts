import Foundation
import Testing

@testable import WorkoutsKit

/// A scripted `MediaSource`: writes `size` bytes to a fresh file per fetch for ids in `videos`, nil for the rest,
/// throws for ids in `failing`. Counts every fetch (and the Wi-Fi-only flag) behind a lock.
nonisolated final class FakeMediaSource: MediaSource, @unchecked Sendable {
    struct Failure: Error, Equatable {}

    private let lock = NSLock()
    private let directory: URL
    private let videos: [String: Int]
    private let failing: Set<String>
    private let delay: Duration?
    private var fetches: [String] = []
    private var cellularFlags: [Bool] = []

    init(directory: URL, videos: [String: Int], failing: Set<String> = [], delay: Duration? = nil) {
        self.directory = directory
        self.videos = videos
        self.failing = failing
        self.delay = delay
    }

    /// `"<id>/<scheme>"` for every fetch, in order.
    var requests: [String] { lock.withLock { fetches } }
    var allowsCellularFlags: [Bool] { lock.withLock { cellularFlags } }

    func fetchVideo(sourceId: String, scheme: MediaScheme) async throws -> URL? {
        try await fetchVideo(sourceId: sourceId, scheme: scheme, allowsCellular: true)
    }

    func fetchVideo(sourceId: String, scheme: MediaScheme, allowsCellular: Bool) async throws -> URL? {
        lock.withLock {
            fetches.append("\(sourceId)/\(scheme.rawValue)")
            cellularFlags.append(allowsCellular)
        }
        if let delay { try await Task.sleep(for: delay) }
        if failing.contains(sourceId) { throw Failure() }
        guard let size = videos[sourceId] else { return nil }
        let file = directory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data(repeating: 7, count: size).write(to: file)
        return file
    }
}

/// A source whose fetches block until `release()`, and which fails Wi-Fi-only fetches the way a cellular network does.
nonisolated final class GatedMediaSource: MediaSource, @unchecked Sendable {
    struct Offline: Error {}

    private let lock = NSLock()
    private let directory: URL
    private var gateOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var flags: [Bool] = []

    init(directory: URL) { self.directory = directory }

    var allowsCellularFlags: [Bool] { lock.withLock { flags } }

    func release() {
        let pending = lock.withLock {
            gateOpen = true
            defer { waiters = [] }
            return waiters
        }
        for waiter in pending { waiter.resume() }
    }

    func fetchVideo(sourceId: String, scheme: MediaScheme) async throws -> URL? {
        try await fetchVideo(sourceId: sourceId, scheme: scheme, allowsCellular: true)
    }

    func fetchVideo(sourceId: String, scheme: MediaScheme, allowsCellular: Bool) async throws -> URL? {
        lock.withLock { flags.append(allowsCellular) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let open = lock.withLock {
                if !gateOpen { waiters.append(continuation) }
                return gateOpen
            }
            if open { continuation.resume() }
        }
        if !allowsCellular { throw Offline() }
        let file = directory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data(repeating: 7, count: 10).write(to: file)
        return file
    }
}

@Suite(.serialized) struct MediaStoreTests {
    func withStore(
        capBytes: Int64 = MediaStore.defaultCapBytes,
        videos: [String: Int] = [:],
        failing: Set<String> = [],
        delay: Duration? = nil,
        _ body: (MediaStore, FakeMediaSource, URL) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MediaStoreTests-\(UUID().uuidString)"
        )
        let cache = root.appendingPathComponent("cache")
        let scratch = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = FakeMediaSource(directory: scratch, videos: videos, failing: failing, delay: delay)
        let store = MediaStore(source: source, bundle: .main, cacheDirectory: cache, capBytes: capBytes)
        try await body(store, source, cache)
    }

    @Test func missFillsTheCacheThenHitMakesNoSecondFetch() async throws {
        try await withStore(videos: ["abc": 100]) { store, source, _ in
            let first = try #require(try await store.video(for: "abc", scheme: .light))
            let second = try #require(try await store.video(for: "abc", scheme: .light))
            #expect(first == second)
            #expect(first.path.hasSuffix("media/abc/video-light.mp4"))
            #expect(try Data(contentsOf: first).count == 100)
            #expect(source.requests == ["abc/light"])
        }
    }

    @Test func darkSchemeFillsTheDarkFile() async throws {
        try await withStore(videos: ["abc": 10]) { store, source, _ in
            let url = try #require(try await store.video(for: "abc", scheme: .dark))
            #expect(url.lastPathComponent == "video-dark.mp4")
            #expect(source.requests == ["abc/dark"])
            #expect(store.cachedVideoURL(for: "abc", scheme: .light) == nil)
        }
    }

    @Test func noRecordGivesNilAndCachesNothing() async throws {
        try await withStore { store, source, _ in
            let miss = try await store.video(for: "missing", scheme: .light)
            #expect(miss == nil)
            #expect(store.cachedVideoURL(for: "missing", scheme: .light) == nil)
            #expect(await store.cacheSize() == 0)
            // A miss is not remembered: a later fetch asks the source again.
            let again = try await store.video(for: "missing", scheme: .light)
            #expect(again == nil)
            #expect(source.requests == ["missing/light", "missing/light"])
        }
    }

    @Test func noSourceGivesNil() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MediaStoreTests-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: cache) }
        let store = MediaStore(source: nil, bundle: .main, cacheDirectory: cache)
        let none = try await store.video(for: "abc", scheme: .light)
        #expect(none == nil)
    }

    @Test func sourceFailureThrowsLeavesNothingAndRecovers() async throws {
        try await withStore(videos: ["x": 5], failing: ["x"]) { store, source, _ in
            await #expect(throws: FakeMediaSource.Failure()) {
                try await store.video(for: "x", scheme: .light)
            }
            #expect(source.requests == ["x/light"])
            #expect(await store.cacheSize() == 0)
        }
        // The failed task is cleared, so a later success works.
        try await withStore(videos: ["x": 5]) { store, _, _ in
            let url = try await store.video(for: "x", scheme: .light)
            #expect(url != nil)
        }
    }

    @Test func concurrentRequestsShareOneFetch() async throws {
        try await withStore(videos: ["abc": 50], delay: .milliseconds(300)) { store, source, _ in
            async let a = store.video(for: "abc", scheme: .light)
            async let b = store.video(for: "abc", scheme: .light)
            async let c = store.video(for: "abc", scheme: .light)
            let urls = try await [a, b, c].compactMap { $0 }
            #expect(urls.count == 3)
            #expect(Set(urls).count == 1)
            #expect(source.requests.count == 1)
        }
    }

    @Test func invalidSourceIDsAreRejectedWithoutAFetch() async throws {
        try await withStore { store, source, _ in
            for bad in ["", "..", "a/b", "../x"] {
                await #expect(throws: MediaError.invalidSourceID(bad)) {
                    try await store.video(for: bad, scheme: .light)
                }
                #expect(store.cachedVideoURL(for: bad, scheme: .light) == nil)
            }
            #expect(source.requests.isEmpty)
        }
    }

    @Test func evictsLeastRecentlyUsedUnderTinyCap() async throws {
        try await withStore(capBytes: 25, videos: ["a": 10, "b": 10, "c": 10]) { store, source, _ in
            let a = try #require(try await store.video(for: "a", scheme: .light))
            let b = try #require(try await store.video(for: "b", scheme: .light))
            // Make the order unambiguous: a oldest, then b.
            let fm = FileManager.default
            try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -300)], ofItemAtPath: a.path)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -200)], ofItemAtPath: b.path)
            // Touching a through a cache hit makes b the least recently used.
            _ = try await store.video(for: "a", scheme: .light)
            _ = try await store.video(for: "c", scheme: .light)

            #expect(store.cachedVideoURL(for: "a", scheme: .light) != nil)
            #expect(store.cachedVideoURL(for: "b", scheme: .light) == nil)
            #expect(store.cachedVideoURL(for: "c", scheme: .light) != nil)
            #expect(await store.cacheSize() == 20)
            // The cache hit on a did not reach the source.
            #expect(source.requests == ["a/light", "b/light", "c/light"])
        }
    }

    @Test func newFileIsKeptEvenWhenLargerThanCap() async throws {
        try await withStore(capBytes: 5, videos: ["big": 10]) { store, _, _ in
            let url = try #require(try await store.video(for: "big", scheme: .light))
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func installLeavesNoPartialFileBehind() async throws {
        try await withStore(videos: ["abc": 10]) { store, _, cache in
            _ = try await store.video(for: "abc", scheme: .light)
            let folder = cache.appendingPathComponent("media/abc")
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            #expect(names == ["video-light.mp4"])
        }
    }

    @Test func cachedVideoURLIsNilBeforeAndSetAfter() async throws {
        try await withStore(videos: ["abc": 10]) { store, source, _ in
            #expect(store.cachedVideoURL(for: "abc", scheme: .light) == nil)
            let url = try await store.video(for: "abc", scheme: .light)
            #expect(store.cachedVideoURL(for: "abc", scheme: .light) == url)
            #expect(store.cachedVideoURL(for: "abc", scheme: .dark) == nil)
            #expect(source.requests.count == 1)
        }
    }

    @Test func prefetchFetchesAllSkipsFailuresAndReportsProgress() async throws {
        try await withStore(videos: ["a": 10, "c": 10, "d": 10], failing: ["d"]) { store, source, _ in
            let ticks = ProgressTicks()
            let failed = await store.prefetch(sourceIDs: ["a", "b", "c", "d"], scheme: .light, allowsCellular: false) {
                done,
                total in
                ticks.record(done, total)
            }
            #expect(failed == ["d"])
            #expect(store.cachedVideoURL(for: "a", scheme: .light) != nil)
            #expect(store.cachedVideoURL(for: "b", scheme: .light) == nil)
            #expect(store.cachedVideoURL(for: "c", scheme: .light) != nil)
            #expect(store.cachedVideoURL(for: "d", scheme: .light) == nil)
            // The failed fetch (d) is not counted as done.
            #expect(ticks.values == [1, 2, 3, 3])
            #expect(ticks.totals == [4, 4, 4, 4])
            #expect(source.allowsCellularFlags == [false, false, false, false])
        }
    }

    @Test func prefetchSkipsWhatIsAlreadyCached() async throws {
        try await withStore(videos: ["a": 10, "b": 10]) { store, source, _ in
            _ = try await store.video(for: "a", scheme: .light)
            await store.prefetch(sourceIDs: ["a", "b"], scheme: .light)
            #expect(source.requests == ["a/light", "b/light"])
        }
    }

    @Test func cacheSizeAndClearCache() async throws {
        try await withStore(videos: ["a": 30, "b": 12]) { store, _, _ in
            #expect(await store.cacheSize() == 0)
            _ = try await store.video(for: "a", scheme: .light)
            _ = try await store.video(for: "b", scheme: .dark)
            #expect(await store.cacheSize() == 42)
            await store.clearCache()
            #expect(await store.cacheSize() == 0)
            #expect(store.cachedVideoURL(for: "a", scheme: .light) == nil)
        }
    }

    @Test func cellularRequestIsNotStarvedByAHeldWiFiOnlyFetch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = GatedMediaSource(directory: root)
        let store = MediaStore(source: source, bundle: .main, cacheDirectory: root.appendingPathComponent("cache"))

        let bulk = Task { try await store.video(for: "abc", scheme: .light, allowsCellular: false) }
        while source.allowsCellularFlags.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        let onDemand = Task { try await store.video(for: "abc", scheme: .light, allowsCellular: true) }
        while source.allowsCellularFlags.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        // The on-demand request made its own cellular-allowed fetch instead of joining the Wi-Fi-only one.
        #expect(source.allowsCellularFlags == [false, true])
        source.release()

        #expect(try await onDemand.value != nil)
        await #expect(throws: GatedMediaSource.Offline.self) { try await bulk.value }
    }

    @Test func fetchCompletingAfterClearCacheLeavesTheCacheEmpty() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = GatedMediaSource(directory: root)
        let store = MediaStore(source: source, bundle: .main, cacheDirectory: root.appendingPathComponent("cache"))

        let fetch = Task { try await store.video(for: "abc", scheme: .light) }
        while source.allowsCellularFlags.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        await store.clearCache()
        source.release()

        #expect(try await fetch.value == nil)
        #expect(await store.cacheSize() == 0)
        #expect(store.cachedVideoURL(for: "abc", scheme: .light) == nil)
        // A request after the clear fetches and caches normally.
        #expect(try await store.video(for: "abc", scheme: .light) != nil)
        #expect(await store.cacheSize() == 10)
    }

    @Test func thumbnailURLIsNilForAMissingID() async throws {
        try await withStore { store, _, _ in
            #expect(store.thumbnailURL(for: UUID(), phase: .start) == nil)
            #expect(store.thumbnailURL(for: UUID(), phase: .end) == nil)
        }
    }

    @Test func thumbnailURLFindsABundledFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MediaBundle-\(UUID().uuidString).bundle"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let thumbs = root.appendingPathComponent("Library/thumbs")
        try FileManager.default.createDirectory(at: thumbs, withIntermediateDirectories: true)
        let id = UUID()
        try Data([1]).write(to: thumbs.appendingPathComponent("\(id.uuidString)-start.png"))
        let bundle = try #require(Bundle(url: root))
        let store = MediaStore(source: nil, bundle: bundle, cacheDirectory: root)
        #expect(store.thumbnailURL(for: id, phase: .start)?.lastPathComponent == "\(id.uuidString)-start.png")
        #expect(store.thumbnailURL(for: id, phase: .end) == nil)
    }

    @Test func schemeFileNamesAndPhases() {
        #expect(MediaScheme.light.fileName == "video-light.mp4")
        #expect(MediaScheme.dark.fileName == "video-dark.mp4")
        #expect(MediaPhase.allCases.map(\.rawValue) == ["start", "end"])
    }

    @Test func twoArgumentSourceGetsTheDefaultCellularOverload() async throws {
        struct TwoArg: MediaSource {
            func fetchVideo(sourceId: String, scheme: MediaScheme) async throws -> URL? { nil }
        }
        let result = try await TwoArg().fetchVideo(sourceId: "a", scheme: .light, allowsCellular: false)
        #expect(result == nil)
    }
}

/// Collects `prefetch` progress callbacks (they arrive on the store's executor).
nonisolated final class ProgressTicks: @unchecked Sendable {
    private let lock = NSLock()
    private var pairs: [(Int, Int)] = []
    func record(_ done: Int, _ total: Int) { lock.withLock { pairs.append((done, total)) } }
    var values: [Int] { lock.withLock { pairs.map(\.0) } }
    var totals: [Int] { lock.withLock { pairs.map(\.1) } }
}
