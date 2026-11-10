import Foundation

/// The part of a Live Activity that never changes while it runs. The app's `ActivityAttributes` wraps it next to
/// ``WorkoutActivityState``.
public nonisolated struct WorkoutActivityStaticInfo: Codable, Hashable, Sendable {
    /// The in-progress workout the activity belongs to.
    public var workoutID: UUID

    public init(workoutID: UUID) {
        self.workoutID = workoutID
    }
}

/// The set the Live Activity and the rest-end notification point at: the first unchecked set after the most recently
/// checked one (`ActiveWorkoutEngine.activityState`), which is also the set **Done set** would check. Values are
/// display-ready: what checking it would record (typed value, else Previous, else the template plan).
public nonisolated struct WorkoutActivitySet: Codable, Hashable, Sendable {
    /// The set Done checks.
    public var setID: UUID
    /// Exercise name at the time, shortened to ``WorkoutActivityState/maxNameLength`` characters.
    public var exerciseName: String
    /// 1-based position in the exercise ("Set 3 of 4").
    public var number: Int
    /// Sets in the exercise.
    public var count: Int
    public var kind: SetKind
    public var weight: Double?
    public var unit: WeightUnit
    public var reps: Int?
    public var durationSeconds: Int?
    /// Done would be refused (``ActiveWorkoutError/emptySet``): nothing to record even after autofill.
    public var isEmpty: Bool

    public init(
        setID: UUID,
        exerciseName: String,
        number: Int,
        count: Int,
        kind: SetKind = .normal,
        weight: Double? = nil,
        unit: WeightUnit = .lb,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        isEmpty: Bool = false
    ) {
        self.setID = setID
        self.exerciseName = exerciseName
        self.number = number
        self.count = count
        self.kind = kind
        self.weight = weight
        self.unit = unit
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.isEmpty = isEmpty
    }

    /// "Set 3 of 4" for the lock screen and the Island.
    public var progressText: String { "Set \(number) of \(count)" }

    /// "27.5 lb × 8", "12 reps", "0:45", "" when there is nothing to show.
    public var detailText: String {
        formatSetDetail(weight: weight, unit: unit, reps: reps, durationSeconds: durationSeconds)
    }

    /// The next-set part of the rest-end notification: "Set 3 · 27.5 lb × 8" ("Set 1 (warm-up) · 60 lb × 5" for other
    /// kinds, "Set 3" when there are no values).
    public var nextSetText: String {
        let label = "Set \(number)" + (kind == .normal ? "" : " (\(formatKind(kind)))")
        return detailText.isEmpty ? label : "\(label) · \(detailText)"
    }
}

/// What a Live Activity shows. Small on purpose: ActivityKit caps the encoded state at 4 KB (names are shortened, one
/// set is carried, the timers are dates the system renders itself).
public nonisolated struct WorkoutActivityState: Codable, Hashable, Sendable {
    /// Longest exercise or workout name kept; longer ones end with an ellipsis.
    public static let maxNameLength = 60

    public var workoutName: String
    /// The elapsed timer is `Text(timerInterval: startedAt...)`, never a counter.
    public var startedAt: Date
    /// When the running rest ends, nil when none runs (also the `staleDate`). Never a counter.
    public var restEndsAt: Date?
    /// Length of the running rest in seconds (the ring's total), nil when none runs.
    public var restTotal: Int?
    /// Checked sets, warm-ups included.
    public var setsDone: Int
    /// All sets of the workout.
    public var setsTotal: Int
    /// The next set to work (see ``ActiveWorkoutEngine/activityState``); nil when every set is checked.
    public var current: WorkoutActivitySet?

    public init(
        workoutName: String,
        startedAt: Date,
        restEndsAt: Date? = nil,
        restTotal: Int? = nil,
        setsDone: Int = 0,
        setsTotal: Int = 0,
        current: WorkoutActivitySet? = nil
    ) {
        self.workoutName = workoutName
        self.startedAt = startedAt
        self.restEndsAt = restEndsAt
        self.restTotal = restTotal
        self.setsDone = setsDone
        self.setsTotal = setsTotal
        self.current = current
    }

    /// True while a rest is on the clock (an over rest inside its grace still counts).
    public var isResting: Bool { restEndsAt != nil }

    /// True when a rest exists and its end is at or before `date`. The views pair it with `context.isStale` (the
    /// activity goes stale at ``restEndsAt``) so "Rest over" shows without the app running.
    public func isRestOver(at date: Date) -> Bool {
        guard let restEndsAt else { return false }
        return restEndsAt <= date
    }

    /// The whole rest, start to end, for the progress ring. Falls back to 60 s when the total is unknown; nil when no
    /// rest runs.
    public func restRange() -> ClosedRange<Date>? {
        guard let end = restEndsAt else { return nil }
        let total = TimeInterval(max(1, restTotal ?? 60))
        return end.addingTimeInterval(-total)...end
    }

    /// Which ring the Island draws. `restOver` wins over any range; a rest that exists but whose end has passed
    /// without `restOver` is still `.running` (the system clamps the drained ring itself).
    public func ringKind(restOver: Bool) -> RingKind {
        if restOver { return .over }
        if let range = restRange() { return .running(range) }
        return .idle
    }
}

/// The Island ring's three looks: a full `ok` checkmark ring, the draining rest ring over the whole rest, or the glyph
/// alone.
public nonisolated enum RingKind: Equatable, Sendable {
    case over
    case running(ClosedRange<Date>)
    case idle
}

// MARK: - Engine mapping

extension ActiveWorkoutEngine {
    /// The Live Activity content for the in-progress workout, nil without one.
    ///
    /// The current set is the **first unchecked set after the most recently checked one** in
    /// ``activitySetOrder(groups:counts:)`` (exercises by `position`, sets by `position`, adjacent exercises of one
    /// superset group alternating A1, B1, A2, B2, ...), so a set skipped earlier does not hold the activity back. With
    /// none left after it the first unchecked set overall; with nothing checked yet, the first unchecked set.
    public var activityState: WorkoutActivityState? {
        guard let workout = liveWorkout else { return nil }
        let rest = restTimer
        let rows = sortedExercises(of: workout)
        let rowSets = rows.map { sortedSets(of: $0) }
        let order = activitySetOrder(groups: rows.map(\.supersetGroup), counts: rowSets.map(\.count))
        let total = rowSets.reduce(0) { $0 + $1.count }
        let done = rowSets.reduce(0) { $0 + $1.filter(\.completed).count }
        var current: WorkoutActivitySet?
        if let position = currentPosition(in: order, sets: rowSets) {
            let row = rows[position.exercise]
            let sets = rowSets[position.exercise]
            let set = sets[position.set]
            let filled = filledValues(of: set, in: row)
            current = WorkoutActivitySet(
                setID: set.id,
                exerciseName: shortenedName(row.exerciseName, limit: WorkoutActivityState.maxNameLength),
                number: position.set + 1,
                count: sets.count,
                kind: set.kind,
                weight: filled.weight,
                unit: row.unit,
                reps: filled.reps,
                durationSeconds: filled.duration,
                isEmpty: !hasValues(weight: filled.weight, reps: filled.reps, duration: filled.duration, row: row)
            )
        }
        return WorkoutActivityState(
            workoutName: shortenedName(workout.name, limit: WorkoutActivityState.maxNameLength),
            startedAt: workout.startedAt,
            restEndsAt: rest.endsAt,
            restTotal: rest.total,
            setsDone: done,
            setsTotal: total,
            current: current
        )
    }

    /// The set the activity points at, per the rule on ``activityState``. "Most recently checked" is the latest
    /// `completedAt`; a tie (or a missing time) goes to the later set in `order`.
    private func currentPosition(in order: [ActivitySetPosition], sets: [[WorkoutSet]]) -> ActivitySetPosition? {
        var latest: (index: Int, at: Date)?
        for (index, position) in order.enumerated() {
            let set = sets[position.exercise][position.set]
            guard set.completed else { continue }
            let at = set.completedAt ?? .distantPast
            if latest == nil || at >= latest!.at { latest = (index, at) }
        }
        let start = latest.map { $0.index + 1 } ?? 0
        let isOpen: (ActivitySetPosition) -> Bool = { !sets[$0.exercise][$0.set].completed }
        return order[start...].first(where: isOpen) ?? order.first(where: isOpen)
    }

    /// The static part of the activity, nil without a workout.
    public var activityStaticInfo: WorkoutActivityStaticInfo? {
        liveWorkout.map { WorkoutActivityStaticInfo(workoutID: $0.id) }
    }
}

/// Where a set sits: indices into the exercises (by position) and into that exercise's sets (by position).
nonisolated struct ActivitySetPosition: Equatable {
    var exercise: Int
    var set: Int
}

/// The order sets are worked in. Exercises sharing a non-nil superset group that are adjacent form a block; inside a
/// block the order is A1, B1, C1, A2, B2, C2, ... (an exercise with fewer sets drops out once exhausted). Exercises
/// outside a superset keep the plain order (all of A's sets, then all of B's).
/// - Parameters:
///   - groups: `supersetGroup` of each exercise, in position order.
///   - counts: number of sets of each exercise, in the same order.
nonisolated func activitySetOrder(groups: [Int?], counts: [Int]) -> [ActivitySetPosition] {
    var order: [ActivitySetPosition] = []
    var start = 0
    while start < counts.count {
        var end = start + 1
        if let group = groups[start] {
            while end < counts.count, groups[end] == group { end += 1 }
        }
        let block = start..<end
        if block.count == 1 {
            order += (0..<max(0, counts[start])).map { ActivitySetPosition(exercise: start, set: $0) }
        } else {
            let longest = block.map { counts[$0] }.max() ?? 0
            for set in 0..<max(0, longest) {
                for exercise in block where set < counts[exercise] {
                    order.append(ActivitySetPosition(exercise: exercise, set: set))
                }
            }
        }
        start = end
    }
    return order
}

// MARK: - Formatting

/// `name` cut to `limit` characters, the last one an ellipsis when something was removed.
public nonisolated func shortenedName(_ name: String, limit: Int) -> String {
    guard limit > 0, name.count > limit else { return name }
    return String(name.prefix(limit - 1)) + "…"
}

/// The value part of a set: `27.5 lb × 8`. A weight of 0 or none is dropped, so a bodyweight set reads `12 reps`. A
/// duration reads `0:45`, with a weight `20 lb × 0:45`; a weight alone reads `27.5 lb`. Empty when there is nothing
/// to show.
public nonisolated func formatSetDetail(
    weight: Double?,
    unit: WeightUnit,
    reps: Int?,
    durationSeconds: Int?
) -> String {
    let load = (weight ?? 0) > 0 ? weight.map { WeightFormat.text($0, unit: unit) } : nil
    let amount: String? =
        if let reps, reps > 0 {
            load == nil ? "\(reps) \(reps == 1 ? "rep" : "reps")" : "\(reps)"
        } else if let durationSeconds, durationSeconds > 0 {
            ClockFormat.clock(seconds: durationSeconds)
        } else {
            nil
        }
    switch (load, amount) {
    case (let load?, let amount?): return "\(load) × \(amount)"
    case (let load?, nil): return load
    case (nil, let amount?): return amount
    case (nil, nil): return ""
    }
}

/// Display name of a set kind: `warm-up`, `drop`, `failure`; `normal` for a normal set.
public nonisolated func formatKind(_ kind: SetKind) -> String {
    switch kind {
    case .warmup: "warm-up"
    case .normal: "normal"
    case .drop: "drop"
    case .failure: "failure"
    }
}
