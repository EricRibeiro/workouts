/// Total volume of a session's sets in the display unit, rounded to 0.5.
///
/// "`sum(weight x reps)` over counted sets, converted to the display unit, rounded to 0.5. A set with no weight adds
/// nothing, so bodyweight volume is 0 (added weight counts); timed sets add nothing; assisted volume is 0."
public nonisolated func volume(of sets: [LoggedSet], weightType: WeightType, displayUnit: WeightUnit) -> Double {
    guard weightType.category != .assisted else { return 0 }
    let kg = countedSets(sets).reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    return round05(convert(kg, from: .kg, to: displayUnit))
}
