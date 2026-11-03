/// Exactly this many kilograms per pound (spec "Units"; canonical over the reciprocal 2.2046226218).
public nonisolated let kgPerLb = 0.45359237

/// Weights are equal when they differ by less than this many kilograms.
public nonisolated let weightEpsilonKg = 1e-6

/// Weight in kilograms: "compare and sum in kg with exactly `0.45359237` kg per lb".
public nonisolated func toKg(_ weight: Double, unit: WeightUnit) -> Double {
    unit == .lb ? weight * kgPerLb : weight
}

/// "Same-unit conversion returns the value untouched."
public nonisolated func convert(_ weight: Double, from: WeightUnit, to: WeightUnit) -> Double {
    if from == to { return weight }
    return from == .lb ? weight * kgPerLb : weight / kgPerLb
}

/// `Round05`: nearest 0.5. Display only; comparisons use unrounded kg.
public nonisolated func round05(_ value: Double) -> Double {
    (value * 2).rounded() / 2
}

/// "Weights are equal within 1e-6 kg (`100 lb` ties `45.359237 kg`; `17.5 lb` is lighter than `8 kg`)."
public nonisolated func weightsEqual(_ a: Double, _ aUnit: WeightUnit, _ b: Double, _ bUnit: WeightUnit) -> Bool {
    abs(toKg(a, unit: aUnit) - toKg(b, unit: bUnit)) <= weightEpsilonKg
}

/// Three-way compare of two kg values with the 1e-6 tolerance: -1 less, 0 equal, 1 greater.
nonisolated func compareKg(_ a: Double, _ b: Double) -> Int {
    if abs(a - b) <= weightEpsilonKg { return 0 }
    return a < b ? -1 : 1
}
