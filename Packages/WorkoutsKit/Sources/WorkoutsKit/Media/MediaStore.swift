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
    private var inFlight: [String: Task<URL?, any Error>] = [:]

    /// - Parameters:
    ///   - source: Fills the cache on a miss; nil turns videos off (`video(for:scheme:)` returns nil).
    ///   - bundle: Holds `Library/thumbs/<id>-<phase>.png`.
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
        let key = file.path
        if let running = inFlight[key] {
            return try await running.value
        }
        let task = Task { () async throws -> URL? in
            do {
                let fetched = try await source.fetchVideo(
                    sourceId: sourceID,
                    scheme: scheme,
                    allowsCellular: allowsCellular
                )
                let url = try fetched.map { try Self.install($0, at: file) }
                self.finish(key)
                return url
            } catch {
                self.finish(key)
                throw error
            }
        }
        inFlight[key] = task
        let url = try await task.value
        if let url { evict(keeping: url) }
        return url
    }

    /// Best-effort sequential fetch of many videos; failures and missing videos are skipped, cancellation stops early.
    /// `progress` is called after each id with (ids handled so far, total), cached ones included.
    public func prefetch(
        sourceIDs: [String],
        scheme: MediaScheme,
        allowsCellular: Bool = true,
        progress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil
    ) async {
        for (offset, sourceID) in sourceIDs.enumerated() {
            if Task.isCancelled { return }
            _ = try? await video(for: sourceID, scheme: scheme, allowsCellular: allowsCellular)
            progress?(offset + 1, sourceIDs.count)
        }
    }

    // MARK: Cache management

    /// Total bytes of cached files.
    public func cacheSize() -> Int64 {
        cachedFiles().reduce(0) { $0 + $1.size }
    }

    /// Deletes every cached video.
    public func clearCache() {
        try? FileManager.default.removeItem(at: mediaDirectory)
    }

    // MARK: Internals

    private func finish(_ key: String) {
        inFlight[key] = nil
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
