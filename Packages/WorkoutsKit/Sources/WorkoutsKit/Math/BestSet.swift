/// A session's best set.
public nonisolated struct BestSet: Hashable, Sendable {
    /// Index into the sets passed to ``bestSet(in:weightType:options:)``.
    public var index: Int
    /// The set as logged.
    public var set: LoggedSet
    /// The set's weight in the display unit: exact when logged in that unit, otherwise rounded to 0.5.
    public var weightInDisplayUnit: Double
    /// e1RM in the display unit rounded to 0.5; strength types only, otherwise 0.
    public var e1rm: Double
    /// True when `e1rm` came from more than 12 reps.
    public var lowConfidence: Bool

    public init(index: Int, set: LoggedSet, weightInDisplayUnit: Double, e1rm: Double, lowConfidence: Bool) {
        self.index = index
        self.set = set
        self.weightInDisplayUnit = weightInDisplayUnit
        self.e1rm = e1rm
        self.lowConfidence = lowConfidence
    }
}

/// A counted set with its numbers clamped (negative weight/reps/duration/distance = 0), in kg.
nonisolated struct CountedSet {
    var index: Int
    var set: LoggedSet
    var weightKg: Double
    var reps: Int
    var duration: Int
    var distance: Double
}

nonisolated func countedSets(_ sets: [LoggedSet]) -> [CountedSet] {
    sets.enumerated().compactMap { index, set in
        guard set.counts else { return nil }
        return CountedSet(
            index: index,
            set: set,
            weightKg: max(0, toKg(set.weight ?? 0, unit: set.unit)),
            reps: max(0, set.reps ?? 0),
            duration: max(0, set.durationSeconds ?? 0),
            distance: max(0, set.distanceMeters ?? 0)
        )
    }
}

/// First element that no later one strictly beats: ties go to the earlier set.
private nonisolated func pickBest(_ items: [CountedSet], isBetter: (CountedSet, CountedSet) -> Bool) -> CountedSet? {
    var best: CountedSet?
    for item in items where best.map({ isBetter(item, $0) }) ?? true {
        best = item
    }
    return best
}

/// The set's weight in the display unit: "A set's own weight in its own unit is reported exactly as entered;
/// anything converted ... is rounded to the nearest 0.5 in the display unit."
private nonisolated func displayWeight(_ item: CountedSet, _ displayUnit: WeightUnit) -> Double {
    let weight = max(0, item.set.weight ?? 0)
    if item.set.unit == displayUnit { return weight }
    return round05(convert(item.weightKg, from: .kg, to: displayUnit))
}

private nonisolated func result(_ item: CountedSet, _ options: RecordsOptions, estimate: E1RMEstimate? = nil) -> BestSet
{
    BestSet(
        index: item.index,
        set: item.set,
        weightInDisplayUnit: displayWeight(item, options.displayUnit),
        e1rm: estimate.map { round05(convert($0.value, from: .kg, to: options.displayUnit)) } ?? 0,
        lowConfidence: estimate?.lowConfidence ?? false
    )
}

/// Best set of a session, or nil when there is no counted set.
///
/// - Strength: "highest e1RM (a confident estimate beats a low-confidence one); ties: heavier weight, more reps,
///   earlier set. A set needs weight > 0 and >= 1 rep; a session with none falls back to the rep-type rule."
/// - Rep types: "most reps; ties: heavier added weight, earlier set. No reps anywhere (timed): longest duration, tie
///   longer distance; no durations either: longest distance. Reps always beat durations."
/// - Assisted: "typical reps" = the upper median of reps of counted sets with >= 1 rep; keep sets with at least that
///   many reps, pick the lowest assistance; ties: more reps, earlier set. No reps at all: duration rule.
///
/// If counted sets exist but carry no reps, duration or distance, the first counted set is returned (the spec says
/// "none if no counted set", so this never returns nil for a non-empty counted list).
public nonisolated func bestSet(in sets: [LoggedSet], weightType: WeightType, options: RecordsOptions) -> BestSet? {
    let counted = countedSets(sets)
    guard let first = counted.first else { return nil }

    switch weightType.category {
    case .strength:
        if let best = strengthBest(counted, options) { return best }
        return repBest(counted, options) ?? result(first, options)
    case .repBased:
        return repBest(counted, options) ?? result(first, options)
    case .assisted:
        return assistedBest(counted, options) ?? result(first, options)
    }
}

private nonisolated func strengthBest(_ counted: [CountedSet], _ options: RecordsOptions) -> BestSet? {
    let formula = options.formula
    func estimate(_ s: CountedSet) -> E1RMEstimate { e1rm(weight: s.weightKg, reps: s.reps, formula: formula) }
    let candidates = counted.filter { $0.weightKg > 0 && $0.reps >= 1 }
    let best = pickBest(candidates) { a, b in
        let ea = estimate(a)
        let eb = estimate(b)
        if ea.lowConfidence != eb.lowConfidence { return !ea.lowConfidence }
        let byE1RM = compareKg(ea.value, eb.value)
        if byE1RM != 0 { return byE1RM > 0 }
        let byWeight = compareKg(a.weightKg, b.weightKg)
        if byWeight != 0 { return byWeight > 0 }
        return a.reps > b.reps
    }
    return best.map { result($0, options, estimate: estimate($0)) }
}

private nonisolated func repBest(_ counted: [CountedSet], _ options: RecordsOptions) -> BestSet? {
    let withReps = counted.filter { $0.reps >= 1 }
    if !withReps.isEmpty {
        let best = pickBest(withReps) { a, b in
            if a.reps != b.reps { return a.reps > b.reps }
            return compareKg(a.weightKg, b.weightKg) > 0
        }
        return best.map { result($0, options) }
    }
    return timedBest(counted, options)
}

/// Duration rule: longest duration, tie longer distance; no durations: longest distance.
private nonisolated func timedBest(_ counted: [CountedSet], _ options: RecordsOptions) -> BestSet? {
    let timed = counted.filter { $0.duration > 0 }
    if !timed.isEmpty {
        let best = pickBest(timed) { a, b in
            if a.duration != b.duration { return a.duration > b.duration }
            return compareKg(a.distance, b.distance) > 0
        }
        return best.map { result($0, options) }
    }
    let travelled = counted.filter { $0.distance > 0 }
    return pickBest(travelled) { compareKg($0.distance, $1.distance) > 0 }.map { result($0, options) }
}

/// Upper median of `reps` (the element at `count / 2` once sorted): `[4,8,8]` -> 8, `[1,8]` -> 8, `[8,10]` -> 10.
nonisolated func upperMedian(_ reps: [Int]) -> Int? {
    guard !reps.isEmpty else { return nil }
    return reps.sorted()[reps.count / 2]
}

private nonisolated func assistedBest(_ counted: [CountedSet], _ options: RecordsOptions) -> BestSet? {
    let withReps = counted.filter { $0.reps >= 1 }
    guard let typical = upperMedian(withReps.map(\.reps)) else { return timedBest(counted, options) }
    let best = pickBest(withReps.filter { $0.reps >= typical }) { a, b in
        let byAssistance = compareKg(a.weightKg, b.weightKg)
        if byAssistance != 0 { return byAssistance < 0 }
        return a.reps > b.reps
    }
    return best.map { result($0, options) }
}
