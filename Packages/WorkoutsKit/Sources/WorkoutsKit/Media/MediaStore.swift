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

    /// The file served at `<baseURL>/<sourceId>/<fileName>`.
    public var fileName: String { "video-\(rawValue).mp4" }
}

public nonisolated enum MediaError: Error, Equatable, Sendable {
    /// The server answered with a status outside 200...299.
    case badStatus(Int)
    /// The response was not HTTP.
    case notHTTP
    /// The source id is empty or would escape the cache folder.
    case invalidSourceID(String)
}

/// Bundled thumbnails and on-demand cached exercise videos (see `docs/port/media.md`).
///
/// An `actor`, so downloads and cache bookkeeping never run on the main actor and concurrent requests for the same
/// file share one download. Only Foundation; compiles on macOS.
public actor MediaStore {
    /// Info.plist key holding the media base URL.
    public nonisolated static let baseURLInfoKey = "WorkoutsMediaBaseURL"
    public nonisolated static let defaultCapBytes: Int64 = 2 * 1024 * 1024 * 1024

    private nonisolated let baseURL: URL
    private nonisolated let bundle: Bundle
    private nonisolated let mediaDirectory: URL
    private nonisolated let session: URLSession
    private nonisolated let capBytes: Int64
    private var inFlight: [String: Task<URL, any Error>] = [:]

    /// - Parameters:
    ///   - baseURL: Server root; videos live at `<baseURL>/<sourceId>/video-<scheme>.mp4`.
    ///   - bundle: Holds `Library/thumbs/<id>-<phase>.png`.
    ///   - cacheDirectory: Typically `Caches`; files go to `<cacheDirectory>/media/<sourceId>/<file>`.
    ///   - session: Injectable for tests.
    ///   - capBytes: Least-recently-used files are evicted past this total.
    public init(
        baseURL: URL,
        bundle: Bundle,
        cacheDirectory: URL,
        session: URLSession = .shared,
        capBytes: Int64 = MediaStore.defaultCapBytes
    ) {
        self.baseURL = baseURL
        self.bundle = bundle
        self.mediaDirectory = cacheDirectory.appendingPathComponent("media", isDirectory: true)
        self.session = session
        self.capBytes = capBytes
    }

    // MARK: Base URL

    /// Reads `WorkoutsMediaBaseURL` from the bundle's Info.plist.
    public nonisolated static func baseURL(from bundle: Bundle) -> URL? {
        baseURL(fromInfo: bundle.infoDictionary)
    }

    /// Parses the `WorkoutsMediaBaseURL` entry of an Info.plist dictionary; nil unless it is an http(s) URL with a host.
    public nonisolated static func baseURL(fromInfo info: [String: Any]?) -> URL? {
        guard let raw = (info?[baseURLInfoKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty,
            let url = URL(string: raw),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host() != nil
        else { return nil }
        return url
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

    /// A local file URL for the video, downloading it first when it is not cached.
    public func video(for sourceID: String, scheme: MediaScheme) async throws -> URL {
        let file = try fileURL(for: sourceID, scheme: scheme)
        if FileManager.default.fileExists(atPath: file.path) {
            touch(file)
            return file
        }
        let key = file.path
        if let running = inFlight[key] {
            return try await running.value
        }
        let remote = baseURL.appendingPathComponent(sourceID).appendingPathComponent(scheme.fileName)
        let task = Task { [session] () async throws -> URL in
            do {
                let url = try await Self.download(remote, to: file, session: session)
                self.finish(key)
                return url
            } catch {
                self.finish(key)
                throw error
            }
        }
        inFlight[key] = task
        let url = try await task.value
        evict(keeping: url)
        return url
    }

    /// Best-effort sequential download of many videos; failures are skipped, cancellation stops early.
    public func prefetch(sourceIDs: [String], scheme: MediaScheme) async {
        for sourceID in sourceIDs {
            if Task.isCancelled { return }
            _ = try? await video(for: sourceID, scheme: scheme)
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

    /// Downloads to a temporary file, then moves it into place so a reader never sees a partial file.
    private nonisolated static func download(_ remote: URL, to file: URL, session: URLSession) async throws -> URL {
        let (temp, response) = try await session.download(from: remote)
        let fm = FileManager.default
        defer { try? fm.removeItem(at: temp) }
        guard let http = response as? HTTPURLResponse else { throw MediaError.notHTTP }
        guard (200..<300).contains(http.statusCode) else { throw MediaError.badStatus(http.statusCode) }
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
        try fm.moveItem(at: temp, to: file)
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
