import Foundation

/// Polls until `condition` holds, up to `timeout` (the full suite runs loaded, so a fixed sleep is flaky). Returns whether it
/// held, so callers `#expect` or `#require` it and a regression fails the test instead of hanging it.
func eventually(timeout: Duration = .seconds(30), _ condition: () -> Bool) async throws -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        try await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}
