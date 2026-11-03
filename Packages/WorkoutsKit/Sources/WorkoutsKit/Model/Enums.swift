/// Kind of a logged set. Closed enum: `warmup|normal|drop|failure` (data-model.md invariant 9).
public nonisolated enum SetKind: String, Codable, CaseIterable, Sendable {
    case warmup
    case normal
    case drop
    case failure
}

/// Weight unit. Closed enum: `lb|kg`.
public nonisolated enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case lb
    case kg
}

/// How an exercise's `weight` field is interpreted.
public nonisolated enum WeightCategory: String, Codable, CaseIterable, Sendable {
    /// Weight is the load; there is an e1RM.
    case strength
    /// Weight is an optional added weight; the number of reps is what counts.
    case repBased
    /// Weight is the assistance; lower is better.
    case assisted
}

/// The exercise's weight type (spec section 1, `Exercise.weightType`).
public nonisolated enum WeightType: String, Codable, CaseIterable, Sendable {
    case barbell
    case bodyweight
    case dumbbell
    case machine
    case unweighted
    case weighted
    case assisted
    case band

    /// "Strength = `barbell`, `dumbbell`, `machine`, `weighted` and any unknown type (weight = load); Rep types =
    /// `bodyweight`, `unweighted`, `band` (weight = optional added weight); Assisted = `assisted`."
    public var category: WeightCategory {
        switch self {
        case .barbell, .dumbbell, .machine, .weighted: .strength
        case .bodyweight, .unweighted, .band: .repBased
        case .assisted: .assisted
        }
    }

    /// Category for a raw string from storage; "any unknown type" is strength.
    public static func category(forRawValue rawValue: String) -> WeightCategory {
        WeightType(rawValue: rawValue)?.category ?? .strength
    }
}

/// e1RM formula; Epley is the default.
public nonisolated enum E1RMFormula: String, Codable, CaseIterable, Sendable {
    case epley
    case brzycki
}

/// Bar type of an exercise row (default `olympic`).
public nonisolated enum BarType: String, Codable, CaseIterable, Sendable {
    case olympic
    case ez
    case none
    case custom
}
