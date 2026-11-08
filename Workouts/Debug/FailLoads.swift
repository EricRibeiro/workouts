import Foundation

/// `-failHistoryLoads <n>` (Debug builds only): makes the first `n` History summary reads fail, so a UI test can look at the
/// error state and its Retry. A no-op without the argument and in Release, where the body compiles away.
enum FailLoads {
    private static var consumed = 0

    /// True while the launch argument's budget of failures is not used up; each call that returns true spends one.
    static func consumeHistory() -> Bool {
        #if DEBUG
            guard consumed < UserDefaults.standard.integer(forKey: "failHistoryLoads") else { return false }
            consumed += 1
            return true
        #else
            return false
        #endif
    }
}
