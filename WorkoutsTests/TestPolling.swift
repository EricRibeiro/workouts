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
    // Past the deadline: let jobs already queued ahead of this poller (a debounced callback, a main-actor test) run once
    // before the verdict, since a loaded host can put one queue lap past the deadline.
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(20))
    return condition()
}

/// A count of "it happened" events for a callback under test, so a test awaits the callback itself instead of polling a
/// counter. Under load, polling races the callback for the main actor and can lose by a whole queue lap; awaiting the
/// signal cannot. `timeout` is a backstop only: it ends the wait so a regression fails instead of hanging.
final class CallSignal {
    private var pending = 0
    private var waiter: (count: Int, continuation: CheckedContinuation<Bool, Never>)?

    /// Call from the callback under test.
    func fire() {
        pending += 1
        if let waiter, pending >= waiter.count {
            pending -= waiter.count
            self.waiter = nil
            waiter.continuation.resume(returning: true)
        }
    }

    /// Waits until `count` more `fire()`s have happened (ones that already happened count). Returns false when the
    /// backstop expires first. One waiter at a time.
    func wait(count: Int = 1, timeout: Duration = .seconds(120)) async -> Bool {
        if pending >= count {
            pending -= count
            return true
        }
        let backstop = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.expire()
        }
        defer { backstop.cancel() }
        return await withCheckedContinuation { continuation in
            waiter = (count, continuation)
        }
    }

    private func expire() {
        guard let waiter else { return }
        self.waiter = nil
        waiter.continuation.resume(returning: false)
    }
}
