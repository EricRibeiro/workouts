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
