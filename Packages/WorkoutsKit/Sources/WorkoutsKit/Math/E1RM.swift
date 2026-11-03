/// Estimated one-rep max and whether it came from too many reps to trust.
public nonisolated struct E1RMEstimate: Hashable, Sendable {
    public var value: Double
    public var lowConfidence: Bool

    public init(value: Double, lowConfidence: Bool) {
        self.value = value
        self.lowConfidence = lowConfidence
    }
}

/// More than this many reps is a low-confidence estimate (`LowConfidenceReps`).
public nonisolated let lowConfidenceReps = 12

/// Estimated 1RM, in the unit of `weight` (the formulas are linear in weight).
///
/// "Epley `w * (1 + reps / 30)`; Brzycki `w * 36 / (37 - reps)`, undefined from 37 reps (Epley used instead). 1 rep =
/// the weight; 0 reps or weight <= 0 = 0. More than 12 reps returns `lowConfidence = true` and feeds the formula reps
/// clamped at 12."
public nonisolated func e1rm(weight: Double, reps: Int, formula: E1RMFormula) -> E1RMEstimate {
    guard weight > 0, reps > 0 else { return E1RMEstimate(value: 0, lowConfidence: false) }
    if reps == 1 { return E1RMEstimate(value: weight, lowConfidence: false) }
    let low = reps > lowConfidenceReps
    let r = Double(min(reps, lowConfidenceReps))
    let value: Double
    switch formula {
    case .epley: value = weight * (1 + r / 30)
    case .brzycki: value = weight * 36 / (37 - r)  // r <= 12, so 37 - r never reaches 0
    }
    return E1RMEstimate(value: value, lowConfidence: low)
}

/// Whether `candidate` strictly beats `current`: "A confident estimate always beats a low-confidence one, however
/// large; between two low-confidence values the larger wins" (and between two confident ones, the larger). Both
/// values must be in the same unit. Equal values do not beat each other.
public nonisolated func betterE1RM(_ candidate: E1RMEstimate, _ current: E1RMEstimate) -> Bool {
    if candidate.lowConfidence != current.lowConfidence { return !candidate.lowConfidence }
    return candidate.value > current.value
}
