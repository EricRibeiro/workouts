/// Total volume of a session's sets in the display unit, rounded to 0.5.
///
/// "`sum(weight x reps)` over counted sets, converted to the display unit, rounded to 0.5. A set with no weight adds
/// nothing, so bodyweight volume is 0 (added weight counts); timed sets add nothing; assisted volume is 0."
public nonisolated func volume(of sets: [LoggedSet], weightType: WeightType, displayUnit: WeightUnit) -> Double {
    displayedVolume(kg: volumeKg(of: sets, weightType: weightType), displayUnit: displayUnit)
}

/// Unrounded volume of a session's sets in kg (0 for assisted). Sum these across sessions and round once with
/// ``displayedVolume(kg:displayUnit:)``: rounding each session first and then summing drifts by up to 0.25 per session.
public nonisolated func volumeKg(of sets: [LoggedSet], weightType: WeightType) -> Double {
    guard weightType.category != .assisted else { return 0 }
    return countedSets(sets).reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
}

/// A kg volume (one session's, or the total of several) in the display unit, rounded to 0.5. The one place volume is
/// rounded, so the History row, the workout detail and the Finish sheet agree.
public nonisolated func displayedVolume(kg: Double, displayUnit: WeightUnit) -> Double {
    round05(convert(kg, from: .kg, to: displayUnit))
}
