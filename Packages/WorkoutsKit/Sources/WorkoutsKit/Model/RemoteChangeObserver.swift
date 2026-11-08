import CoreData
import Foundation

/// Calls `onChange` once after a burst of `NSPersistentStoreRemoteChange` notifications, the documented signal that the
/// CloudKit mirror merged changes from another device into the store (PLAN 8.1, review C-11 b). The app installs one
/// when sync is on, and the handler re-reads what the app keeps as snapshots: the custom exercises
/// (``ExerciseStore/reloadCustom(from:)``), the engine's Previous values (``ActiveWorkoutEngine/reloadPrevious()``) and
/// the ``StoreGeneration`` bump that refreshes the history caches.
///
/// The mirror posts several notifications per import (and one per local save that history tracking sees), so the
/// handler runs `debounce` after the last one.
public final class RemoteChangeObserver {
    private let center: NotificationCenter
    private let name: Notification.Name
    private let debounce: Duration
    private let clock: any Clock<Duration>
    private let onChange: () -> Void
    private var token: (any NSObjectProtocol)?
    private var pending: Task<Void, Never>?

    /// Whether a handler call is waiting out the debounce. Tests read it to prove `stop()` left nothing armed.
    var isScheduled: Bool { pending != nil }
    /// How many notifications reached the debounce (not counting ones dropped after `stop()`); tests await it so a burst
    /// is fully in before they move the clock.
    private(set) var scheduleCount = 0

    /// - Parameters:
    ///   - name: The notification to watch; tests pass their own.
    ///   - debounce: Quiet time after the last notification before `onChange` runs.
    ///   - clock: Times the debounce; tests pass a manual one.
    public init(
        center: NotificationCenter = .default,
        name: Notification.Name = .NSPersistentStoreRemoteChange,
        debounce: Duration = .seconds(1),
        clock: any Clock<Duration> = ContinuousClock(),
        onChange: @escaping () -> Void
    ) {
        self.center = center
        self.name = name
        self.debounce = debounce
        self.clock = clock
        self.onChange = onChange
    }

    /// Starts listening. Calling it twice listens once.
    public func start() {
        guard token == nil else { return }
        token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in self?.schedule() }
        }
    }

    /// Stops listening and drops a handler call that is waiting.
    public func stop() {
        if let token { center.removeObserver(token) }
        token = nil
        pending?.cancel()
        pending = nil
    }

    private func schedule() {
        // A notification that hopped to the main actor before `stop()` ran must not restart the wait.
        guard token != nil else { return }
        scheduleCount += 1
        pending?.cancel()
        let wait = debounce
        let clock = clock
        pending = Task { [weak self] in
            try? await clock.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.pending = nil
            self?.onChange()
        }
    }
}
