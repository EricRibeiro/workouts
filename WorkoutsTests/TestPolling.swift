import Foundation

/// Polls until `condition` holds, up to `timeout` (a loaded host makes any fixed sleep flaky: `./dev ui-test` runs three
/// simulators next to the unit tests). Returns whether it held, so callers `#expect` it and a regression fails the test
/// instead of hanging it.
func eventually(timeout: Duration = .seconds(30), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}
