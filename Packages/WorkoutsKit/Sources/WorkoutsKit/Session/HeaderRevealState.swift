//
//  HeaderRevealState.swift
//  WorkoutsKit
//

/// The scroll phases the header rule cares about; the app maps SwiftUI's `ScrollPhase` onto these.
public enum HeaderScrollPhase: Sendable, Equatable {
    case idle
    case tracking
    case interacting
    case decelerating
    /// A programmatic scroll (`scrollTo`): its ending never restarts the timer.
    case animating
}

/// When the logging screen's title header comes back: the system minimises it while the set table scrolls down, and
/// `restoreDelay` after a user scroll ends it is pinned visible again. The next scroll unpins it so it can hide again.
///
/// A pure value so the timing rule is testable without waiting: the view keeps one `@State` of this, runs a
/// `.task(id: generation)` that sleeps `restoreDelay`, then calls `restoreTimerFired(generation:)`.
public struct HeaderRevealState: Sendable, Equatable {
    public static let restoreDelay: Duration = .milliseconds(1500)

    /// True while the header is held visible (the minimisation behaviour is `.never`).
    public private(set) var isPinned = false
    /// Bumped by every scroll start and every user-scroll end; a timer started for an older value is stale.
    public private(set) var generation = 0
    /// A user scroll ended and the restore timer for the current `generation` should run.
    public private(set) var isRestorePending = false

    public init() {}

    /// Feed every scroll-phase change here.
    public mutating func phaseChanged(from old: HeaderScrollPhase, to new: HeaderScrollPhase) {
        if new == .idle {
            // Only a finger lifting or a fling settling starts the timer.
            guard old == .decelerating || old == .interacting else { return }
            isRestorePending = true
            generation += 1
        } else {
            isRestorePending = false
            generation += 1
            isPinned = false
        }
    }

    /// The restore timer for `generation` elapsed. Returns whether the header was pinned; a stale generation (a scroll
    /// began or ended since) is ignored.
    @discardableResult
    public mutating func restoreTimerFired(generation fired: Int) -> Bool {
        guard fired == generation, isRestorePending else { return false }
        isRestorePending = false
        isPinned = true
        return true
    }
}
