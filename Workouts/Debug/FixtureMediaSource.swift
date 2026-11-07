import Foundation
import WorkoutsKit

/// `-mediaSource fixture[:delayMs]` (Debug builds only): a `MediaSource` that needs no network, so a UI test can run the
/// Settings "Download all videos" feature under `-uiTesting` (PLAN 7b.6). Each fetch waits `delayMs` (default 0), then
/// writes a tiny file for the requested id and hands it to the store, which copies it into the cache.
nonisolated struct FixtureMediaSource: MediaSource {
    let delay: Duration

    /// The source the launch arguments ask for, nil without `-mediaSource fixture`.
    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> FixtureMediaSource? {
        guard let flag = arguments.firstIndex(of: "-mediaSource"), flag + 1 < arguments.count else { return nil }
        let value = arguments[flag + 1]
        guard value == "fixture" || value.hasPrefix("fixture:") else { return nil }
        let milliseconds = value.split(separator: ":").dropFirst().first.flatMap { Int($0) } ?? 0
        return FixtureMediaSource(delay: .milliseconds(max(milliseconds, 0)))
    }

    func fetchVideo(sourceId: String, scheme: MediaScheme) async throws -> URL? {
        if delay > .zero { try await Task.sleep(for: delay) }
        let folder = URL.temporaryDirectory.appendingPathComponent(
            "fixture-media-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(scheme.fileName, isDirectory: false)
        try Data("fixture \(sourceId) \(scheme.rawValue)".utf8).write(to: file)
        return file
    }
}
