import Foundation

/// Which frame of an exercise's two-frame thumbnail pair.
public nonisolated enum MediaPhase: String, Sendable, CaseIterable {
    case start
    case end
}

/// Which video variant to use; the kit has no SwiftUI `ColorScheme`.
public nonisolated enum MediaScheme: String, Sendable, CaseIterable {
    case light
    case dark

    /// The cached file name, `video-<scheme>.mp4`.
    public var fileName: String { "video-\(rawValue).mp4" }
}

public nonisolated enum MediaError: Error, Equatable, Sendable {
    /// The source id is empty or would escape the cache folder.
    case invalidSourceID(String)
}

/// Where videos come from when the cache misses (CloudKit's public database in the app; a fake in tests).
///
/// The kit never imports CloudKit: the app supplies a conforming type. A source only produces a local file; caching,
/// the LRU cap and de-duplication of concurrent requests stay in `MediaStore`.
public nonisolated protocol MediaSource: Sendable {
    /// A local file holding the video, or nil when the source has no video for that id (and scheme). The store copies
    /// the file into its cache, so the source may hand back a file it owns. Throws for transient failures.
    func fetchVideo(sourceId: String, scheme: MediaScheme) async throws -> URL?

    /// As `fetchVideo(sourceId:scheme:)`, but a bulk download can ask for Wi-Fi only. The default ignores the flag.
    func fetchVideo(sourceId: String, scheme: MediaScheme, allowsCellular: Bool) async throws -> URL?
}

extension MediaSource {
    public func fetchVideo(sourceId: String, scheme: MediaScheme, allowsCellular: Bool) async throws -> URL? {
        try await fetchVideo(sourceId: sourceId, scheme: scheme)
    }
}

/// Bundled thumbnails and on-demand cached exercise videos (see `docs/port/media.md`).
///
/// An `actor`, so cache bookkeeping never runs on the main actor and concurrent requests for the same file share one
/// fetch. Only Foundation; compiles on macOS.
public actor MediaStore {
    public nonisolated static let defaultCapBytes: Int64 = 2 * 1024 * 1024 * 1024

    private nonisolated let source: (any MediaSource)?
    private nonisolated let bundle: Bundle
    private nonisolated let mediaDirectory: URL
    private nonisolated let capBytes: Int64
    private nonisolated let cropCache: ThumbnailCropCache
    private struct InFlightFetch {
        let id: UUID
        let task: Task<URL?, any Error>
    }

    /// Keyed by file path and network policy (see `video(for:scheme:allowsCellular:)`).
    private var inFlight: [String: InFlightFetch] = [:]
    /// Bumped by `clearCache()`; a fetch that started in an older generation never installs its file.
    private var generation = 0

    /// - Parameters:
    ///   - source: Fills the cache on a miss; nil turns videos off (`video(for:scheme:)` returns nil).
    ///   - bundle: Holds `Library/thumbs/<id>-<phase>.png` and `Library/thumbs/thumb-crops.json`.
    ///   - cacheDirectory: Typically `Caches`; files go to `<cacheDirectory>/media/<sourceId>/video-<scheme>.mp4`.
    ///   - capBytes: Least-recently-used files are evicted past this total.
    public init(
        source: (any MediaSource)?,
        bundle: Bundle,
        cacheDirectory: URL,
        capBytes: Int64 = MediaStore.defaultCapBytes
    ) {
        self.source = source
        self.bundle = bundle
        self.cropCache = ThumbnailCropCache(bundle: bundle)
        self.mediaDirectory = cacheDirectory.appendingPathComponent("media", isDirectory: true)
        self.capBytes = capBytes
    }

    // MARK: Thumbnails

    /// The bundled thumbnail for a library exercise, or nil when the bundle has none.
    public nonisolated func thumbnailURL(for id: UUID, phase: MediaPhase) -> URL? {
        bundle.url(
            forResource: "\(id.uuidString)-\(phase.rawValue)",
            withExtension: "png",
            subdirectory: "Library/thumbs"
        )
    }

    /// Where the figure sits in a library exercise's thumbnails (the union of its start and end frames), or nil when the
    /// bundle has no crop manifest or no entry for the id. The manifest is read once, on the first call.
    public nonisolated func thumbnailCrop(for id: UUID) -> CropRect? {
        cropCache.crop(for: id)
    }

    // MARK: Videos

    /// The cached video if present, without touching the network or its LRU date.
    public nonisolated func cachedVideoURL(for sourceID: String, scheme: MediaScheme) -> URL? {
        guard let file = try? fileURL(for: sourceID, scheme: scheme),
            FileManager.default.fileExists(atPath: file.path)
        else { return nil }
        return file
    }

    /// A local file URL for the video, fetching it from the source first when it is not cached. Nil when there is no
    /// source or the source has no video for this id. Throws what the source throws; nothing is retried.
    public func video(for sourceID: String, scheme: MediaScheme, allowsCellular: Bool = true) async throws -> URL? {
        let file = try fileURL(for: sourceID, scheme: scheme)
        if FileManager.default.fileExists(atPath: file.path) {
            touch(file)
            return file
        }
        guard let source else { return nil }
        // A fetch is shared only with one that is at least as permissive: a cellular-allowed request must never wait on a
        // Wi-Fi-only fetch (which fails on cellular and starves it), while a Wi-Fi-only one may ride a cellular fetch.
        let cellularKey = "\(file.path)|cellular"
        let key = allowsCellular ? cellularKey : "\(file.path)|wifi"
        if let running = inFlight[cellularKey] ?? inFlight[key] {
            return try await running.task.value
        }
        let fetchID = UUID()
        let startedIn = generation
        let task = Task { () async throws -> URL? in
            defer { self.finish(key, id: fetchID) }
            let fetched = try await source.fetchVideo(
                sourceId: sourceID,
                scheme: scheme,
                allowsCellular: allowsCellular
            )
            // `clearCache()` ran while this was downloading (Remove must stick): drop the download instead of
            // installing it. Callers get nil, the same as "no video", since nothing is cached for them.
            guard generation == startedIn else { return nil }
            return try fetched.map { try Self.install($0, at: file) }
        }
        inFlight[key] = InFlightFetch(id: fetchID, task: task)
        let url = try await task.value
        if let url { evict(keeping: url) }
        return url
    }

    /// The ids among `sourceIDs` whose video is not in the cache yet, in order. Synchronous file-existence checks
    /// only (no network, no LRU touch), so a UI can size a progress bar before any download starts. An id that cannot
    /// name a cache file counts as uncached.
    public nonisolated func uncachedSourceIDs(in sourceIDs: [String], scheme: MediaScheme) -> [String] {
        sourceIDs.filter { cachedVideoURL(for: $0, scheme: scheme) == nil }
    }

    /// Best-effort sequential fetch of many videos; cancellation stops early. Videos already cached are counted as done
    /// up front and not revisited, so a repeated pass starts where the cache already is rather than at zero. A video the
    /// source does not have (nil) is handled, since there is nothing to fetch; one whose fetch **threw** (offline,
    /// Wi-Fi-only on cellular) is not: its id is returned so the caller can retry it later. `progress` is called after
    /// each fetched id with (ids handled so far, total), cached and missing ones included, failed ones not.
    @discardableResult
    public func prefetch(
        sourceIDs: [String],
        scheme: MediaScheme,
        allowsCellular: Bool = true,
        progress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil
    ) async -> [String] {
        let pending = uncachedSourceIDs(in: sourceIDs, scheme: scheme)
        let alreadyCached = sourceIDs.count - pending.count
        var failed: [String] = []
        for (offset, sourceID) in pending.enumerated() {
            if Task.isCancelled { return failed }
            do {
                _ = try await video(for: sourceID, scheme: scheme, allowsCellular: allowsCellular)
            } catch is CancellationError {
                return failed
            } catch {
                failed.append(sourceID)
            }
            progress?(alreadyCached + offset + 1 - failed.count, sourceIDs.count)
        }
        return failed
    }

    // MARK: Cache management

    /// Total bytes of cached files.
    public func cacheSize() -> Int64 {
        cachedFiles().reduce(0) { $0 + $1.size }
    }

    /// Deletes every cached video. Fetches still downloading are forgotten (a later request starts afresh) and discard
    /// their file when they finish, so nothing reappears after the clear.
    public func clearCache() {
        generation += 1
        inFlight.removeAll()
        try? FileManager.default.removeItem(at: mediaDirectory)
    }

    // MARK: Internals

    /// Clears the entry only if it is still this fetch's (a clear may have replaced it with a newer one).
    private func finish(_ key: String, id: UUID) {
        if inFlight[key]?.id == id { inFlight[key] = nil }
    }

    private nonisolated func fileURL(for sourceID: String, scheme: MediaScheme) throws -> URL {
        guard !sourceID.isEmpty, sourceID != ".", sourceID != "..", !sourceID.contains("/"), !sourceID.contains("\0")
        else { throw MediaError.invalidSourceID(sourceID) }
        return mediaDirectory.appendingPathComponent(sourceID, isDirectory: true)
            .appendingPathComponent(scheme.fileName, isDirectory: false)
    }

    private nonisolated func touch(_ file: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
    }

    /// Copies the source's file next to its destination, then moves it into place so a reader never sees a partial file.
    private nonisolated static func install(_ fetched: URL, at file: URL) throws -> URL {
        let fm = FileManager.default
        let folder = file.deletingLastPathComponent()
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = folder.appendingPathComponent(".\(UUID().uuidString).partial", isDirectory: false)
        defer { try? fm.removeItem(at: partial) }
        try fm.copyItem(at: fetched, to: partial)
        if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
        try fm.moveItem(at: partial, to: file)
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return file
    }

    private struct CachedFile {
        var url: URL
        var size: Int64
        var modified: Date
    }

    private func cachedFiles() -> [CachedFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard
            let walker = FileManager.default.enumerator(
                at: mediaDirectory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        else { return [] }
        var files: [CachedFile] = []
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }
            files.append(
                CachedFile(
                    url: url,
                    size: Int64(values.fileSize ?? 0),
                    modified: values.contentModificationDate ?? .distantPast
                )
            )
        }
        return files
    }

    /// Removes least-recently-used files until the cache fits `capBytes`; `keeping` is never removed.
    private func evict(keeping keep: URL) {
        var files = cachedFiles()
        var total = files.reduce(Int64(0)) { $0 + $1.size }
        guard total > capBytes else { return }
        files.sort { $0.modified < $1.modified }
        let fm = FileManager.default
        for file in files where total > capBytes {
            if file.url.standardizedFileURL == keep.standardizedFileURL { continue }
            do {
                try fm.removeItem(at: file.url)
                total -= file.size
                let folder = file.url.deletingLastPathComponent()
                if (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                    try? fm.removeItem(at: folder)
                }
            } catch {
                continue
            }
        }
    }
}
