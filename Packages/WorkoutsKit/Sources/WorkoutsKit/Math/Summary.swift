/// Per-session numbers shown on a History card.
public nonisolated struct SessionSummary: Hashable, Sendable {
    public var best: BestSet?
    public var volume: Double
    /// Reps over counted sets.
    public var totalReps: Int
    /// Every completed set, warm-ups included: the `N x` of a History card.
    public var setCount: Int
    /// Number of counted sets (completed, not warm-up).
    public var working: Int

    public init(best: BestSet?, volume: Double, totalReps: Int, setCount: Int, working: Int) {
        self.best = best
        self.volume = volume
        self.totalReps = totalReps
        self.setCount = setCount
        self.working = working
    }
}

/// `Summarize`: `Best`, `Volume`, `TotalReps` (reps over counted sets), `SetCount` (every completed set, warm-ups
/// included) and `Working` (number of counted sets).
public nonisolated func summarize(_ session: Session, options: RecordsOptions) -> SessionSummary {
    let counted = countedSets(session.sets)
    return SessionSummary(
        best: bestSet(in: session.sets, weightType: session.weightType, options: options),
        volume: volume(of: session.sets, weightType: session.weightType, displayUnit: options.displayUnit),
        totalReps: counted.reduce(0) { $0 + $1.reps },
        setCount: session.sets.filter(\.completed).count,
        working: counted.count
    )
}
