import Foundation

/// Why an ``ActiveWorkoutEngine`` call was refused. Save failures are not mapped: the underlying error is thrown.
public nonisolated enum ActiveWorkoutError: Error, Equatable, Sendable {
    /// "Workout in progress": a workout is already running (its name, for the sheet's message).
    case workoutInProgress(name: String)
    /// The call needs the in-progress workout and there is none.
    case noActiveWorkout
    /// "Check a set with nothing to record ... refused": nothing to record even after autofill.
    case emptySet
    /// "Nothing logged yet": finishing needs at least one checked set.
    case nothingLogged
    /// The exercise or set does not belong to the in-progress workout.
    case notInActiveWorkout
    /// The order passed to `reorderExercises` is not a permutation of the workout's exercises.
    case invalidOrder
}

extension ActiveWorkoutError: LocalizedError {
    /// Short English sentences for the save-error alert.
    public var errorDescription: String? {
        switch self {
        case .workoutInProgress(let name): "A workout is already in progress (\(name))."
        case .noActiveWorkout: "There is no workout in progress."
        case .emptySet: "There is nothing to record in this set."
        case .nothingLogged: "Nothing has been logged yet."
        case .notInActiveWorkout: "That item is not part of the workout in progress."
        case .invalidOrder: "The exercise order is not valid."
        }
    }
}

/// What to do with unchecked sets that have values when finishing ("Complete Unfinished Sets" / "Discard Unfinished
/// Sets").
public nonisolated enum UnfinishedSets: Sendable, Hashable {
    /// Check them (`completedAt = now`, no rest started).
    case complete
    /// Drop them.
    case discard
}

/// Which Finish dialog the logging screen shows first (`active-workout.md` section 3, Finish).
public nonisolated enum FinishDialog: Sendable, Hashable {
    /// Every set is checked: finish straight away.
    case none
    /// Nothing checked: "Nothing logged yet" with Discard Workout / Keep Going.
    case nothingLogged
    /// Unchecked sets with values: "Finish Workout?" with Complete / Discard Unfinished Sets / Cancel.
    case unfinishedWithValues(count: Int)
    /// Only unchecked sets without values: "N sets are not checked and will not be saved".
    case unfinishedWithoutValues(count: Int)
}

/// The records one exercise set in the finished session.
public nonisolated struct ExercisePRs: Sendable, Hashable {
    public var exerciseID: UUID
    public var exerciseName: String
    public var records: [PersonalRecord]

    public init(exerciseID: UUID, exerciseName: String, records: [PersonalRecord]) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.records = records
    }
}

/// The numbers of the finish sheet plus what the Finish dialogs need.
public nonisolated struct FinishSummary: Sendable, Hashable {
    /// Seconds from `startedAt` to now (before finish) or to `finishedAt` (after), never negative.
    public var duration: TimeInterval
    /// Checked sets, warm-ups included ("Sets").
    public var setCount: Int
    /// Exercises with at least one checked set ("Exercises").
    public var exerciseCount: Int
    /// weight x reps over checked non-warm-up sets, in `volumeUnit`, rounded to 0.5 (assisted exercises add nothing).
    public var volume: Double
    public var volumeUnit: WeightUnit
    /// Records newly set, per exercise, in workout order; exercises without a record are omitted.
    public var prs: [ExercisePRs]
    /// Total number of records across `prs`.
    public var prCount: Int
    /// This workout's ordinal among finished workouts ("Your 615th workout"), counting itself.
    public var workoutNumber: Int
    /// Unchecked sets that have a weight, reps or duration.
    public var uncheckedWithValues: Int
    /// Unchecked sets with nothing entered.
    public var uncheckedWithoutValues: Int
    public var dialog: FinishDialog
    /// The workout this summary describes (it is saved by the time the summary exists); nil for hand-made summaries.
    public var workoutID: UUID?

    public init(
        duration: TimeInterval,
        setCount: Int,
        exerciseCount: Int,
        volume: Double,
        volumeUnit: WeightUnit,
        prs: [ExercisePRs],
        prCount: Int,
        workoutNumber: Int,
        uncheckedWithValues: Int,
        uncheckedWithoutValues: Int,
        dialog: FinishDialog,
        workoutID: UUID? = nil
    ) {
        self.duration = duration
        self.setCount = setCount
        self.exerciseCount = exerciseCount
        self.volume = volume
        self.volumeUnit = volumeUnit
        self.prs = prs
        self.prCount = prCount
        self.workoutNumber = workoutNumber
        self.uncheckedWithValues = uncheckedWithValues
        self.uncheckedWithoutValues = uncheckedWithoutValues
        self.dialog = dialog
        self.workoutID = workoutID
    }
}

/// A set's "Previous" cell: the same set index of the exercise's most recent finished performance, already in the
/// row's unit (converted and rounded to 0.5 when the units differ).
public nonisolated struct PreviousSet: Sendable, Hashable {
    public var kind: SetKind
    public var weight: Double?
    public var reps: Int?
    public var durationSeconds: Int?

    public init(kind: SetKind = .normal, weight: Double? = nil, reps: Int? = nil, durationSeconds: Int? = nil) {
        self.kind = kind
        self.weight = weight
        self.reps = reps
        self.durationSeconds = durationSeconds
    }
}

/// A set's plan: the template's weight, reps and duration for it, shown as placeholders.
public nonisolated struct SetPlan: Sendable, Hashable {
    public var weight: Double?
    public var reps: Int?
    public var durationSeconds: Int?

    public init(weight: Double? = nil, reps: Int? = nil, durationSeconds: Int? = nil) {
        self.weight = weight
        self.reps = reps
        self.durationSeconds = durationSeconds
    }
}
