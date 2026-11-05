import CryptoKit
import Foundation

/// Compiles `Guest/DuoGuest.swift` for the iOS simulator and caches the binary per source + toolchain.
public struct GuestBuilder: Sendable {
    public static let sourceRelativePath = "Tools/duo/Guest/DuoGuest.swift"
    public static let cacheRelativePath = ".build/duo/guest"
    public static let binaryName = "duo-guest"

    public var runner: any ProcessRunning
    public var sourceURL: URL
    public var cacheRoot: URL
    public var lockTimeout: TimeInterval

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        sourceURL: URL,
        cacheRoot: URL,
        lockTimeout: TimeInterval = 120
    ) {
        self.runner = runner
        self.sourceURL = sourceURL
        self.cacheRoot = cacheRoot
        self.lockTimeout = lockTimeout
    }

    /// The builder for a repository checkout rooted at `root`.
    public init(repositoryRoot root: URL, runner: any ProcessRunning = SystemProcessRunner()) {
        self.init(
            runner: runner,
            sourceURL: root.appendingPathComponent(Self.sourceRelativePath),
            cacheRoot: root.appendingPathComponent(Self.cacheRelativePath)
        )
    }

    /// Hex SHA-256 over the source bytes and the toolchain identity, so a source edit or an Xcode/SDK update
    /// lands in a fresh directory.
    public static func cacheKey(source: Data, xcodeVersion: String, sdkVersion: String) -> String {
        var hasher = SHA256()
        hasher.update(data: source)
        for part in [xcodeVersion, sdkVersion] {
            hasher.update(data: Data([0]))
            hasher.update(data: Data(part.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// `swiftc` arguments; the deployment target follows the SDK version (`27.2` gives `arm64-apple-ios27.2-simulator`).
    public static func swiftcArguments(sdkVersion: String, source: String, output: String) -> [String] {
        [
            "-sdk", "iphonesimulator", "swiftc",
            "-target", "arm64-apple-ios\(sdkVersion.trimmingCharacters(in: .whitespacesAndNewlines))-simulator",
            "-O", "-framework", "IOKit", source, "-o", output,
        ]
    }

    /// Directory-and-binary location for the current toolchain, without building.
    public func binaryURL() throws -> URL {
        let (key, _) = try identify()
        return cacheRoot.appendingPathComponent(key).appendingPathComponent(Self.binaryName)
    }

    /// Returns the cached binary, compiling it first (under a lock) when this key has none.
    public func build() throws -> URL {
        let (key, sdkVersion) = try identify()
        let directory = cacheRoot.appendingPathComponent(key)
        let binary = directory.appendingPathComponent(Self.binaryName)
        let manager = FileManager.default
        if manager.isExecutableFile(atPath: binary.path) { return binary }

        return try DirectoryLock.withLock(
            at: cacheRoot.appendingPathComponent("\(key).lock"),
            timeout: lockTimeout
        ) {
            // Another process may have finished while we waited.
            if manager.isExecutableFile(atPath: binary.path) { return binary }
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let partial = directory.appendingPathComponent("\(Self.binaryName).partial")
            try? manager.removeItem(at: partial)
            let arguments = Self.swiftcArguments(sdkVersion: sdkVersion, source: sourceURL.path, output: partial.path)
            try run("/usr/bin/xcrun", arguments)
            try? manager.removeItem(at: binary)
            try manager.moveItem(at: partial, to: binary)
            removeStaleBuilds(keeping: key)
            return binary
        }
    }

    /// Deletes the other `<key>/` directories (older sources or toolchains); `.lock` directories stay.
    private func removeStaleBuilds(keeping key: String) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(atPath: cacheRoot.path) else { return }
        for name in entries where name != key && !name.hasSuffix(".lock") {
            try? manager.removeItem(at: cacheRoot.appendingPathComponent(name))
        }
    }

    private func identify() throws -> (key: String, sdkVersion: String) {
        guard let source = FileManager.default.contents(atPath: sourceURL.path) else {
            throw DuoError.guestSourceMissing(path: sourceURL.path)
        }
        let xcode = try run("/usr/bin/xcrun", ["xcodebuild", "-version"])
        let sdk = try run("/usr/bin/xcrun", ["--sdk", "iphonesimulator", "--show-sdk-version"])
        let sdkVersion = sdk.trimmingCharacters(in: .whitespacesAndNewlines)
        return (Self.cacheKey(source: source, xcodeVersion: xcode, sdkVersion: sdkVersion), sdkVersion)
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let output = try runner.run(executable, arguments: arguments)
        guard output.status == 0 else {
            throw DuoError.commandFailed(
                command: "xcrun " + arguments.joined(separator: " "),
                status: output.status,
                stderr: output.stderr
            )
        }
        return String(decoding: output.stdout, as: UTF8.self)
    }

    /// Walks up from `start` to the first directory that holds `Tools/duo/Guest/DuoGuest.swift`.
    public static func repositoryRoot(startingAt start: URL) -> URL? {
        var directory = start.standardizedFileURL
        while true {
            let candidate = directory.appendingPathComponent(sourceRelativePath).path
            if FileManager.default.fileExists(atPath: candidate) { return directory }
            // deletingLastPathComponent() of "/" is "/../", so stop at the root explicitly.
            if directory.path == "/" { return nil }
            directory = directory.deletingLastPathComponent().standardizedFileURL
        }
    }

    /// The checkout this tool is run from: the working directory's, else the one it was compiled in.
    public static func defaultRepositoryRoot(file: StaticString = #filePath) -> URL? {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let root = repositoryRoot(startingAt: cwd) { return root }
        // <root>/Tools/duo/Sources/DuoKit/GuestBuilder.swift
        var compiled = URL(fileURLWithPath: "\(file)")
        for _ in 0..<5 { compiled.deleteLastPathComponent() }
        return repositoryRoot(startingAt: compiled)
    }
}
