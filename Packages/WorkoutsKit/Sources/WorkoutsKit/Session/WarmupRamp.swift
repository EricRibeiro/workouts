/// One step of a warm-up ramp: a weight in the row's unit and the reps to do with it.
public nonisolated struct WarmupStep: Sendable, Hashable {
    public var weight: Double
    public var reps: Int

    public init(weight: Double, reps: Int) {
        self.weight = weight
        self.reps = reps
    }
}

/// "Add Warm-up Sets" (`workout.md` section 3): from the working weight W, the empty bar x 10, then 40% x 8, 60% x 5
/// and 80% x 3 of W, each rounded to the plate step (5 lb / 2.5 kg). A step not above the previous kept step (or the
/// bar), or reaching W, is omitted. Pure; the engine turns the steps into sets.
public nonisolated enum WarmupRamp {
    /// The percentage steps after the empty bar: (fraction of W, reps).
    static let percentSteps: [(fraction: Double, reps: Int)] = [(0.4, 8), (0.6, 5), (0.8, 3)]
    /// Reps of the empty-bar step.
    static let barReps = 10

    /// Rounding step of ramp weights: 5 lb or 2.5 kg.
    public static func plateStep(for unit: WeightUnit) -> Double {
        unit == .lb ? 5 : 2.5
    }

    /// The bar's weight in the row's `unit`: Olympic 45 lb / 20 kg, EZ 15 lb / 7 kg, none 0, custom the row's
    /// `customWeight` (0 when unset or negative: a custom bar of unknown weight adds no empty-bar step).
    public static func barWeight(for barType: BarType, unit: WeightUnit, customWeight: Double?) -> Double {
        switch barType {
        case .olympic: unit == .lb ? 45 : 20
        case .ez: unit == .lb ? 15 : 7
        case .none: 0
        case .custom: max(0, customWeight ?? 0)
        }
    }

    /// The warm-up steps for working weight `workingWeight`, in the row's unit and bar. With no bar (weight 0) there is
    /// no empty-bar step and the percentage steps only need to be above 0. Empty when `workingWeight` is not above 0
    /// or every step is dropped (for example a 45 lb set on the 45 lb bar).
    public static func steps(
        workingWeight: Double,
        unit: WeightUnit,
        barType: BarType,
        customBarWeight: Double? = nil
    ) -> [WarmupStep] {
        guard workingWeight > 0 else { return [] }
        let bar = barWeight(for: barType, unit: unit, customWeight: customBarWeight)
        let plate = plateStep(for: unit)
        var steps: [WarmupStep] = []
        var previous = bar
        if bar > 0, bar < workingWeight {
            steps.append(WarmupStep(weight: bar, reps: barReps))
        }
        for (fraction, reps) in percentSteps {
            let weight = ((workingWeight * fraction) / plate).rounded() * plate
            guard weight > previous, weight < workingWeight else { continue }
            steps.append(WarmupStep(weight: weight, reps: reps))
            previous = weight
        }
        return steps
    }
}
