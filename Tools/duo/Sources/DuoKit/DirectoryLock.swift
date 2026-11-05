import Foundation

/// A cross-process lock made of one directory: `mkdir` is atomic, and the owner's pid inside it lets a later
/// process reclaim the lock when its owner died (the same scheme as `./dev`'s simulator lock).
public enum DirectoryLock {
    /// Runs `body` while holding the lock at `url`; waits up to `timeout` seconds for a live holder.
    public static func withLock<T>(
        at url: URL,
        timeout: TimeInterval = 120,
        pollInterval: TimeInterval = 0.2,
        isAlive: (Int32) -> Bool = processIsAlive,
        pidlessStaleAfter: TimeInterval = 10,
        body: () throws -> T
    ) throws -> T {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pidFile = url.appendingPathComponent("pid")
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            do {
                try manager.createDirectory(at: url, withIntermediateDirectories: false)
                try Data("\(getpid())\n".utf8).write(to: pidFile)
                break
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                if let holder = holderPid(pidFile) {
                    if !isAlive(holder) {
                        try? manager.removeItem(at: url)
                        continue
                    }
                } else if isOlder(url, than: pidlessStaleAfter) {
                    // The holder died between mkdir and writing its pid; a live one writes it within milliseconds.
                    try? manager.removeItem(at: url)
                    continue
                }
                guard Date() < deadline else { throw DuoError.lockTimeout(path: url.path) }
                Thread.sleep(forTimeInterval: pollInterval)
            }
        }
        defer { try? manager.removeItem(at: url) }
        return try body()
    }

    /// Whether the directory was last modified more than `age` seconds ago.
    static func isOlder(_ url: URL, than age: TimeInterval) -> Bool {
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else { return false }
        return Date().timeIntervalSince(modified) > age
    }

    /// Pid recorded by the holder; nil while the holder is between `mkdir` and writing it.
    static func holderPid(_ pidFile: URL) -> Int32? {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func processIsAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
