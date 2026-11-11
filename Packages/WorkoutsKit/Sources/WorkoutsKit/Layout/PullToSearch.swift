/// The pull-down-to-search rule for a scrolling list: search opens once the content is dragged far enough below its
/// resting top. Pure numbers, so the threshold is testable without a simulator.
public nonisolated enum PullToSearch {
    /// Points of overscroll that count as a pull.
    public static let threshold: Double = 50

    /// True when the content sits at least `threshold` points below its resting top. At rest at the top
    /// `contentOffsetY == -topInset`, so the overscroll is `-(contentOffsetY + topInset)`.
    public static func isPulledPast(
        contentOffsetY: Double,
        topInset: Double,
        threshold: Double = PullToSearch.threshold
    ) -> Bool {
        -(contentOffsetY + topInset) >= threshold
    }
}

/// Opens search after the finger lifts from a pulled-past list, once the scroll view has come back to rest.
public nonisolated struct PullToSearchTrigger: Sendable, Equatable {
    public enum Phase: Sendable { case interacting, settling, idle }

    private var phase: Phase = .idle
    private var isPulled = false
    private var isArmed = false

    public init() {}

    /// The latest answer of `PullToSearch.isPulledPast`.
    public mutating func pulledPast(_ value: Bool) {
        isPulled = value
    }

    /// Feeds a scroll phase change; true when search should open now.
    public mutating func phaseChanged(to newPhase: Phase) -> Bool {
        let previous = phase
        phase = newPhase
        if newPhase == .interacting {
            isArmed = false
            return false
        }
        if previous == .interacting && isPulled { isArmed = true }
        if newPhase == .idle && isArmed {
            isArmed = false
            return true
        }
        return false
    }
}
