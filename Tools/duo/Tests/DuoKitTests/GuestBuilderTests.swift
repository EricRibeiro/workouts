import Foundation
import Testing

@testable import DuoKit

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("duo-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Plays xcodebuild, the SDK query and swiftc; "compiling" writes an executable file to the `-o` path.
private final class ToolchainRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var xcodeVersion: String
    var sdkVersion: String
    var compileStatus: Int32

    init(
        xcodeVersion: String = "Xcode 27.2\nBuild version 27B52\n",
        sdkVersion: String = "27.2\n",
        compileStatus: Int32 = 0
    ) {
        self.xcodeVersion = xcodeVersion
        self.sdkVersion = sdkVersion
        self.compileStatus = compileStatus
    }

    var calls: [[String]] { lock.withLock { recorded } }
    var compileCount: Int { calls.filter { $0.contains("swiftc") }.count }

    func run(_ executable: String, arguments: [String]) throws -> ProcessOutput {
        lock.withLock { recorded.append(arguments) }
        if arguments == ["xcodebuild", "-version"] {
            return ProcessOutput(status: 0, stdout: Data(xcodeVersion.utf8), stderr: "")
        }
        if arguments.contains("--show-sdk-version") {
            return ProcessOutput(status: 0, stdout: Data(sdkVersion.utf8), stderr: "")
        }
        if arguments.contains("swiftc"), let index = arguments.firstIndex(of: "-o") {
            guard compileStatus == 0 else {
                return ProcessOutput(status: compileStatus, stdout: Data(), stderr: "compile error")
            }
            let output = arguments[index + 1]
            FileManager.default.createFile(
                atPath: output,
                contents: Data("binary".utf8),
                attributes: [.posixPermissions: 0o755]
            )
            return ProcessOutput(status: 0, stdout: Data(), stderr: "")
        }
        return ProcessOutput(status: 1, stdout: Data(), stderr: "unexpected \(arguments)")
    }
}

private func makeCheckout(source: String = "print(1)") throws -> URL {
    let root = try temporaryDirectory()
    let guest = root.appendingPathComponent("Tools/duo/Guest")
    try FileManager.default.createDirectory(at: guest, withIntermediateDirectories: true)
    try Data(source.utf8).write(to: guest.appendingPathComponent("DuoGuest.swift"))
    return root
}

@Suite struct CacheKeyTests {
    private let source = Data("print(1)".utf8)

    @Test func sameInputsGiveTheSameKey() {
        let a = GuestBuilder.cacheKey(source: source, xcodeVersion: "Xcode 27.2", sdkVersion: "27.2")
        let b = GuestBuilder.cacheKey(source: source, xcodeVersion: "Xcode 27.2\n", sdkVersion: "27.2\n")
        #expect(a == b)
        #expect(a.count == 64)
    }

    @Test func sourceChangeGivesANewKey() {
        let a = GuestBuilder.cacheKey(source: source, xcodeVersion: "Xcode 27.2", sdkVersion: "27.2")
        let b = GuestBuilder.cacheKey(source: Data("print(2)".utf8), xcodeVersion: "Xcode 27.2", sdkVersion: "27.2")
        #expect(a != b)
    }

    @Test func xcodeOrSDKChangeGivesANewKey() {
        let base = GuestBuilder.cacheKey(source: source, xcodeVersion: "Xcode 27.2", sdkVersion: "27.2")
        #expect(base != GuestBuilder.cacheKey(source: source, xcodeVersion: "Xcode 27.3", sdkVersion: "27.2"))
        #expect(base != GuestBuilder.cacheKey(source: source, xcodeVersion: "Xcode 27.2", sdkVersion: "27.3"))
    }

    @Test func fieldsCannotBleedIntoEachOther() {
        let a = GuestBuilder.cacheKey(source: source, xcodeVersion: "ab", sdkVersion: "c")
        let b = GuestBuilder.cacheKey(source: source, xcodeVersion: "a", sdkVersion: "bc")
        #expect(a != b)
    }

    @Test func swiftcTargetsTheSimulatorSDKVersion() {
        #expect(
            GuestBuilder.swiftcArguments(sdkVersion: "27.2\n", source: "/s.swift", output: "/o")
                == [
                    "-sdk", "iphonesimulator", "swiftc", "-target", "arm64-apple-ios27.2-simulator", "-O", "-framework",
                    "IOKit",
                    "/s.swift", "-o",
                    "/o",
                ]
        )
    }
}

@Suite struct GuestBuildTests {
    @Test func buildsOnceThenHitsTheCache() throws {
        let root = try makeCheckout()
        let runner = ToolchainRunner()
        let builder = GuestBuilder(repositoryRoot: root, runner: runner)
        let first = try builder.build()
        let second = try builder.build()
        #expect(first == second)
        #expect(first.lastPathComponent == "duo-guest")
        #expect(first.path.hasPrefix(root.appendingPathComponent(".build/duo/guest").path))
        #expect(FileManager.default.isExecutableFile(atPath: first.path))
        #expect(runner.compileCount == 1)
    }

    @Test func xcodeUpdateRebuildsIntoANewDirectory() throws {
        let root = try makeCheckout()
        let runner = ToolchainRunner()
        let builder = GuestBuilder(repositoryRoot: root, runner: runner)
        let before = try builder.build()
        runner.xcodeVersion = "Xcode 27.3\nBuild version 27C1\n"
        let after = try builder.build()
        #expect(before != after)
        #expect(runner.compileCount == 2)
    }

    @Test func sourceChangeRebuilds() throws {
        let root = try makeCheckout()
        let runner = ToolchainRunner()
        let builder = GuestBuilder(repositoryRoot: root, runner: runner)
        let before = try builder.build()
        try Data("print(2)".utf8).write(to: root.appendingPathComponent(GuestBuilder.sourceRelativePath))
        let after = try builder.build()
        #expect(before != after)
        #expect(runner.compileCount == 2)
    }

    @Test func aSuccessfulBuildRemovesOlderKeyDirectoriesButNotLocks() throws {
        let root = try makeCheckout()
        let runner = ToolchainRunner()
        let builder = GuestBuilder(repositoryRoot: root, runner: runner)
        let cache = root.appendingPathComponent(".build/duo/guest")
        let first = try builder.build()
        let otherLock = cache.appendingPathComponent("0123.lock")
        try FileManager.default.createDirectory(at: otherLock, withIntermediateDirectories: true)
        try Data("print(2)".utf8).write(to: root.appendingPathComponent(GuestBuilder.sourceRelativePath))
        let second = try builder.build()
        #expect(first != second)
        #expect(!FileManager.default.fileExists(atPath: first.deletingLastPathComponent().path))
        #expect(FileManager.default.isExecutableFile(atPath: second.path))
        #expect(FileManager.default.fileExists(atPath: otherLock.path))
    }

    @Test func aCacheHitLeavesOtherDirectoriesAlone() throws {
        let root = try makeCheckout()
        let builder = GuestBuilder(repositoryRoot: root, runner: ToolchainRunner())
        _ = try builder.build()
        let stray = root.appendingPathComponent(".build/duo/guest/stray")
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        _ = try builder.build()
        #expect(FileManager.default.fileExists(atPath: stray.path))
    }

    @Test func compileFailureLeavesNoBinaryAndNoLock() throws {
        let root = try makeCheckout()
        let runner = ToolchainRunner(compileStatus: 1)
        let builder = GuestBuilder(repositoryRoot: root, runner: runner)
        #expect(throws: DuoError.self) { try builder.build() }
        let cache = root.appendingPathComponent(".build/duo/guest")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []
        #expect(!leftovers.contains { $0.hasSuffix(".lock") })
        #expect(throws: DuoError.self) { try builder.build() }
    }

    @Test func missingSourceIsReported() throws {
        let root = try temporaryDirectory()
        let builder = GuestBuilder(repositoryRoot: root, runner: ToolchainRunner())
        #expect(
            throws: DuoError.guestSourceMissing(path: root.appendingPathComponent(GuestBuilder.sourceRelativePath).path)
        ) {
            try builder.build()
        }
    }

    @Test func findsTheRepositoryRootFromASubdirectory() throws {
        let root = try makeCheckout()
        let nested = root.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(
            GuestBuilder.repositoryRoot(startingAt: nested)?.standardizedFileURL.path == root.standardizedFileURL.path
        )
        #expect(GuestBuilder.repositoryRoot(startingAt: try temporaryDirectory()) == nil)
    }
}

@Suite struct DirectoryLockTests {
    @Test func runsBodyAndReleases() throws {
        let lock = try temporaryDirectory().appendingPathComponent("x.lock")
        let value = try DirectoryLock.withLock(at: lock) { 42 }
        #expect(value == 42)
        #expect(!FileManager.default.fileExists(atPath: lock.path))
    }

    @Test func releasesWhenTheBodyThrows() throws {
        struct Boom: Error {}
        let lock = try temporaryDirectory().appendingPathComponent("x.lock")
        #expect(throws: Boom.self) { try DirectoryLock.withLock(at: lock) { throw Boom() } }
        #expect(!FileManager.default.fileExists(atPath: lock.path))
    }

    @Test func aLiveHolderMakesASecondAcquirerTimeOut() throws {
        let lock = try temporaryDirectory().appendingPathComponent("x.lock")
        _ = try DirectoryLock.withLock(at: lock) {
            #expect(throws: DuoError.lockTimeout(path: lock.path)) {
                try DirectoryLock.withLock(at: lock, timeout: 0.3, pollInterval: 0.05) { 0 }
            }
        }
    }

    @Test func aDeadHoldersLockIsReclaimed() throws {
        let lock = try temporaryDirectory().appendingPathComponent("x.lock")
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: true)
        try Data("999999\n".utf8).write(to: lock.appendingPathComponent("pid"))
        let value = try DirectoryLock.withLock(at: lock, timeout: 1, isAlive: { _ in false }) { "reclaimed" }
        #expect(value == "reclaimed")
    }

    @Test func aPidlessLockOlderThanTenSecondsIsStale() throws {
        let lock = try temporaryDirectory().appendingPathComponent("x.lock")
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -60)],
            ofItemAtPath: lock.path
        )
        let value = try DirectoryLock.withLock(at: lock, timeout: 1) { "reclaimed" }
        #expect(value == "reclaimed")
    }

    @Test func aHolderWithoutAPidFileIsWaitedFor() throws {
        let lock = try temporaryDirectory().appendingPathComponent("x.lock")
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: true)
        #expect(throws: DuoError.lockTimeout(path: lock.path)) {
            try DirectoryLock.withLock(at: lock, timeout: 0.2, pollInterval: 0.05) { 0 }
        }
    }
}
