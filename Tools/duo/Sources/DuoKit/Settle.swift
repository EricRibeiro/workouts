import CryptoKit
import Foundation

/// Waits for the screen to stop changing: captures repeatedly, comparing SHA-256 of consecutive captures, until two
/// are equal. Clock, sleep and capture are injected so the loop runs in tests without a simulator.
public enum Settle {
    public static let defaultTimeout: TimeInterval = 10
    public static let interval: TimeInterval = 0.3

    public struct Result: Sendable, Equatable {
        /// Captures taken, including the first and the final (equal) one.
        public var captures: Int
        /// Seconds from the first capture to the settled one.
        public var elapsed: TimeInterval
        /// Hex SHA-256 of the settled capture.
        public var digest: String

        public var summary: String {
            "settled after \(captures) captures in \(String(format: "%.1f", elapsed)) s (sha256 \(digest))"
        }
    }

    public static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Calls `capture` (which returns the capture's bytes), sleeps `interval`, and repeats until two consecutive
    /// captures hash equal. After a capture that differs, gives up with `DuoError.settleTimeout` once `timeout`
    /// seconds have passed since the first capture. At least two captures are always taken.
    public static func run(
        timeout: TimeInterval = defaultTimeout,
        interval: TimeInterval = Settle.interval,
        now: () -> Date = Date.init,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        capture: () throws -> Data
    ) throws -> Result {
        let start = now()
        var previous = hex(try capture())
        var captures = 1
        while true {
            if now().timeIntervalSince(start) >= timeout {
                throw DuoError.settleTimeout(seconds: timeout, captures: captures)
            }
            sleep(interval)
            let current = hex(try capture())
            captures += 1
            if current == previous {
                return Result(captures: captures, elapsed: now().timeIntervalSince(start), digest: current)
            }
            previous = current
        }
    }
}
