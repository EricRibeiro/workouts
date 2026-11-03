import Foundation

/// One logged set (the spec's `Set`, renamed to avoid `Swift.Set`).
public nonisolated struct LoggedSet: Hashable, Codable, Sendable {
    public var kind: SetKind
    public var weight: Double?
    public var unit: WeightUnit
    public var reps: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var completed: Bool

    public init(
        kind: SetKind = .normal,
        weight: Double? = nil,
        unit: WeightUnit = .kg,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        completed: Bool = true
    ) {
        self.kind = kind
        self.weight = weight
        self.unit = unit
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.completed = completed
    }

    /// "Counted set: `completed` and not `warmup`; drop and failure count. Warm-ups and unchecked sets never reach a
    /// best set, a volume, a chart or a record."
    public var counts: Bool { completed && kind != .warmup }
}

/// One exercise in one workout: the unit every derived number is computed from.
public nonisolated struct Session: Hashable, Codable, Sendable {
    public var workoutID: UUID
    public var time: Date
    public var exerciseID: UUID
    public var weightType: WeightType
    public var sets: [LoggedSet]

    public init(workoutID: UUID, time: Date, exerciseID: UUID, weightType: WeightType, sets: [LoggedSet]) {
        self.workoutID = workoutID
        self.time = time
        self.exerciseID = exerciseID
        self.weightType = weightType
        self.sets = sets
    }
}

/// "`Options` = formula `epley`|`brzycki` plus display unit (zero value = Epley in kg; any unit other than `lb` is kg)."
public nonisolated struct RecordsOptions: Hashable, Codable, Sendable {
    public var formula: E1RMFormula
    public var displayUnit: WeightUnit

    public init(formula: E1RMFormula = .epley, displayUnit: WeightUnit = .kg) {
        self.formula = formula
        self.displayUnit = displayUnit
    }
}
