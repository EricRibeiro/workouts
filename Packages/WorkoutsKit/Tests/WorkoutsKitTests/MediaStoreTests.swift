import Foundation
import Testing

@testable import WorkoutsKit

/// Canned responses for `MediaStoreTests`, keyed by URL path, with a lock-protected request counter.
nonisolated final class FakeMediaProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: (status: Int, body: Data)] = [:]
    nonisolated(unsafe) private static var requests: [String] = []
    nonisolated(unsafe) private static var delay: TimeInterval = 0

    static func reset(responses: [String: (status: Int, body: Data)], delay: TimeInterval = 0) {
        lock.withLock {
            self.responses = responses
            self.requests = []
            self.delay = delay
        }
    }

    static var requestPaths: [String] { lock.withLock { requests } }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeMediaProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let (canned, wait): ((status: Int, body: Data)?, TimeInterval) = Self.lock.withLock {
            Self.requests.append(url.path)
            return (Self.responses[url.path], Self.delay)
        }
        let status = canned?.status ?? 404
        let body = canned?.body ?? Data()
        let respond = { [self] in
            guard
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )
            else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        if wait > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + wait, execute: respond)
        } else {
            respond()
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct MediaStoreTests {
    static let base = URL(string: "https://media.example.test/media/")!

    func withStore(
        capBytes: Int64 = MediaStore.defaultCapBytes,
        responses: [String: (status: Int, body: Data)] = [:],
        delay: TimeInterval = 0,
        _ body: (MediaStore, URL) async throws -> Void
    ) async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MediaStoreTests-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        FakeMediaProtocol.reset(responses: responses, delay: delay)
        let store = MediaStore(
            baseURL: Self.base,
            bundle: .main,
            cacheDirectory: cache,
            session: FakeMediaProtocol.makeSession(),
            capBytes: capBytes
        )
        try await body(store, cache)
    }

    static func ok(_ count: Int) -> (status: Int, body: Data) { (200, Data(repeating: 7, count: count)) }

    @Test func downloadThenCacheHitMakesOneRequest() async throws {
        try await withStore(responses: ["/media/abc/video-light.mp4": Self.ok(100)]) { store, _ in
            let first = try await store.video(for: "abc", scheme: .light)
            let second = try await store.video(for: "abc", scheme: .light)
            #expect(first == second)
            #expect(first.path.hasSuffix("media/abc/video-light.mp4"))
            #expect(try Data(contentsOf: first).count == 100)
            #expect(FakeMediaProtocol.requestPaths == ["/media/abc/video-light.mp4"])
        }
    }

    @Test func darkSchemeFetchesTheDarkFile() async throws {
        try await withStore(responses: ["/media/abc/video-dark.mp4": Self.ok(10)]) { store, _ in
            let url = try await store.video(for: "abc", scheme: .dark)
            #expect(url.lastPathComponent == "video-dark.mp4")
            #expect(FakeMediaProtocol.requestPaths == ["/media/abc/video-dark.mp4"])
        }
    }

    @Test func concurrentRequestsShareOneDownload() async throws {
        try await withStore(responses: ["/media/abc/video-light.mp4": Self.ok(50)], delay: 0.3) { store, _ in
            async let a = store.video(for: "abc", scheme: .light)
            async let b = store.video(for: "abc", scheme: .light)
            async let c = store.video(for: "abc", scheme: .light)
            let urls = try await [a, b, c]
            #expect(Set(urls).count == 1)
            #expect(FakeMediaProtocol.requestPaths.count == 1)
        }
    }

    @Test func notFoundThrowsAndLeavesNothing() async throws {
        try await withStore { store, cache in
            await #expect(throws: MediaError.badStatus(404)) {
                try await store.video(for: "missing", scheme: .light)
            }
            #expect(store.cachedVideoURL(for: "missing", scheme: .light) == nil)
            #expect(await store.cacheSize() == 0)
            let folder = cache.appendingPathComponent("media/missing")
            #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("video-light.mp4").path))
            // A later success still works (the failed task was cleared).
            FakeMediaProtocol.reset(responses: ["/media/missing/video-light.mp4": Self.ok(5)])
            _ = try await store.video(for: "missing", scheme: .light)
            #expect(store.cachedVideoURL(for: "missing", scheme: .light) != nil)
        }
    }

    @Test func serverErrorThrowsBadStatus() async throws {
        try await withStore(responses: ["/media/x/video-light.mp4": (500, Data("boom".utf8))]) { store, _ in
            await #expect(throws: MediaError.badStatus(500)) {
                try await store.video(for: "x", scheme: .light)
            }
            #expect(await store.cacheSize() == 0)
        }
    }

    @Test func invalidSourceIDsAreRejectedWithoutARequest() async throws {
        try await withStore { store, _ in
            for bad in ["", "..", "a/b", "../x"] {
                await #expect(throws: MediaError.invalidSourceID(bad)) {
                    try await store.video(for: bad, scheme: .light)
                }
                #expect(store.cachedVideoURL(for: bad, scheme: .light) == nil)
            }
            #expect(FakeMediaProtocol.requestPaths.isEmpty)
        }
    }

    @Test func evictsLeastRecentlyUsedUnderTinyCap() async throws {
        let responses = ["a", "b", "c"].reduce(into: [String: (status: Int, body: Data)]()) {
            $0["/media/\($1)/video-light.mp4"] = Self.ok(10)
        }
        try await withStore(capBytes: 25, responses: responses) { store, _ in
            let a = try await store.video(for: "a", scheme: .light)
            let b = try await store.video(for: "b", scheme: .light)
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
        }
    }

    @Test func newFileIsKeptEvenWhenLargerThanCap() async throws {
        try await withStore(capBytes: 5, responses: ["/media/big/video-light.mp4": Self.ok(10)]) { store, _ in
            let url = try await store.video(for: "big", scheme: .light)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func cachedVideoURLIsNilBeforeAndSetAfter() async throws {
        try await withStore(responses: ["/media/abc/video-light.mp4": Self.ok(10)]) { store, _ in
            #expect(store.cachedVideoURL(for: "abc", scheme: .light) == nil)
            let url = try await store.video(for: "abc", scheme: .light)
            #expect(store.cachedVideoURL(for: "abc", scheme: .light) == url)
            #expect(store.cachedVideoURL(for: "abc", scheme: .dark) == nil)
            #expect(FakeMediaProtocol.requestPaths.count == 1)
        }
    }

    @Test func prefetchFetchesAllAndSkipsFailures() async throws {
        let responses = [
            "/media/a/video-light.mp4": Self.ok(10),
            "/media/c/video-light.mp4": Self.ok(10),
        ]
        try await withStore(responses: responses) { store, _ in
            await store.prefetch(sourceIDs: ["a", "b", "c"], scheme: .light)
            #expect(store.cachedVideoURL(for: "a", scheme: .light) != nil)
            #expect(store.cachedVideoURL(for: "b", scheme: .light) == nil)
            #expect(store.cachedVideoURL(for: "c", scheme: .light) != nil)
        }
    }

    @Test func cacheSizeAndClearCache() async throws {
        let responses = [
            "/media/a/video-light.mp4": Self.ok(30),
            "/media/b/video-dark.mp4": Self.ok(12),
        ]
        try await withStore(responses: responses) { store, _ in
            #expect(await store.cacheSize() == 0)
            _ = try await store.video(for: "a", scheme: .light)
            _ = try await store.video(for: "b", scheme: .dark)
            #expect(await store.cacheSize() == 42)
            await store.clearCache()
            #expect(await store.cacheSize() == 0)
            #expect(store.cachedVideoURL(for: "a", scheme: .light) == nil)
        }
    }

    @Test func thumbnailURLIsNilForAMissingID() async throws {
        try await withStore { store, _ in
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
        let store = MediaStore(
            baseURL: Self.base,
            bundle: bundle,
            cacheDirectory: root,
            session: FakeMediaProtocol.makeSession()
        )
        #expect(store.thumbnailURL(for: id, phase: .start)?.lastPathComponent == "\(id.uuidString)-start.png")
        #expect(store.thumbnailURL(for: id, phase: .end) == nil)
    }

    @Test func baseURLParsesFromInfoDictionary() {
        let key = MediaStore.baseURLInfoKey
        #expect(key == "WorkoutsMediaBaseURL")
        #expect(
            MediaStore.baseURL(fromInfo: [key: "https://workouts.example.test/media/"])?.absoluteString
                == "https://workouts.example.test/media/"
        )
        #expect(MediaStore.baseURL(fromInfo: [key: "  https://h.test/m  "])?.host() == "h.test")
        #expect(MediaStore.baseURL(fromInfo: [:]) == nil)
        #expect(MediaStore.baseURL(fromInfo: nil) == nil)
        #expect(MediaStore.baseURL(fromInfo: [key: ""]) == nil)
        #expect(MediaStore.baseURL(fromInfo: [key: "not a url"]) == nil)
        #expect(MediaStore.baseURL(fromInfo: [key: "ftp://h.test/m"]) == nil)
        #expect(MediaStore.baseURL(fromInfo: [key: 5]) == nil)
    }

    @Test func baseURLFromBundleReadsInfoPlist() {
        // The test bundle has no WorkoutsMediaBaseURL, so the lookup is nil rather than a crash.
        #expect(MediaStore.baseURL(from: Bundle(for: FakeMediaProtocol.self)) == nil)
    }

    @Test func schemeFileNamesAndPhases() {
        #expect(MediaScheme.light.fileName == "video-light.mp4")
        #expect(MediaScheme.dark.fileName == "video-dark.mp4")
        #expect(MediaPhase.allCases.map(\.rawValue) == ["start", "end"])
    }
}
