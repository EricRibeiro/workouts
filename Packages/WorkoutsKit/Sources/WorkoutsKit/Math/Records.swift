import Foundation

/// A kind of personal record.
public nonisolated enum RecordKind: String, Codable, CaseIterable, Sendable {
    /// Best estimated 1RM.
    case e1rm
    /// Heaviest weight with at least one rep; assisted: the least assistance.
    case heaviest
    /// Best single set, `weight x reps` (not session volume).
    case bestVolumeSet = "volume"
    /// Longest set with a duration, whether or not it also has reps.
    case longestDuration = "duration"
    /// Most reps at one weight.
    case repsAtWeight
}

/// One record and the set that holds it.
public nonisolated struct ExerciseRecord: Hashable, Sendable {
    public var kind: RecordKind
    /// e1RM, weight, volume (display unit), seconds for `longestDuration`, reps for `repsAtWeight`.
    public var value: Double
    /// The holding set's weight in the display unit (exact in its own unit, otherwise rounded to 0.5).
    public var weight: Double
    public var reps: Int
    /// The holding set's duration in seconds (0 when it has none).
    public var durationSeconds: Int
    public var workoutID: UUID
    public var time: Date
    /// True when an e1RM record comes from more than 12 reps (only held when no confident set exists).
    public var lowConfidence: Bool

    public init(
        kind: RecordKind,
        value: Double,
        weight: Double,
        reps: Int,
        durationSeconds: Int,
        workoutID: UUID,
        time: Date,
        lowConfidence: Bool = false
    ) {
        self.kind = kind
        self.value = value
        self.weight = weight
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.workoutID = workoutID
        self.time = time
        self.lowConfidence = lowConfidence
    }
}

/// The set's weight in the display unit: exact when logged in that unit, otherwise converted and rounded to 0.5.
nonisolated func displayedWeight(_ set: CountedSet, unit: WeightUnit) -> Double {
    if set.set.unit == unit { return max(0, set.set.weight ?? 0) }
    return round05(convert(set.weightKg, from: .kg, to: unit))
}

/// An aggregate computed in kg (volume, e1RM) shown in `unit`, rounded to 0.5.
nonisolated func displayedAggregate(kg: Double, unit: WeightUnit) -> Double {
    round05(convert(kg, from: .kg, to: unit))
}

/// The set that holds a record. `key[0]` is the quantity that must be beaten across sessions; the rest only break ties
/// inside one session.
nonisolated struct RecordHolder {
    var key: [Double]
    var set: CountedSet
    /// kg-based (seconds for duration).
    var value: Double
    var low = false
    var workoutID: UUID
    var time: Date
}

nonisolated struct RepsRow {
    var set: CountedSet
    var workoutID: UUID
    var time: Date
}

private nonisolated func lexBetter(_ a: [Double], _ b: [Double]) -> Bool {
    for (x, y) in zip(a, b) {
        let order = compareKg(x, y)
        if order != 0 { return order > 0 }
    }
    return false
}

/// Folds one exercise's sessions, oldest first, into the current records; shared by ``records`` and ``prsInSession``.
nonisolated struct RecordTracker {
    let options: RecordsOptions
    let category: WeightCategory
    var best: [RecordKind: RecordHolder] = [:]
    var rows: [RepsRow] = []

    var inverted: Bool { category == .assisted }

    init(weightType: WeightType, options: RecordsOptions) {
        self.options = options
        self.category = weightType.category
    }

    /// Folds one session in and returns the records it newly set. A record changes only by beating the current one
    /// strictly, so an equal result is not a PR (and the earlier session keeps a tie).
    mutating func add(_ session: Session) -> [PersonalRecord] {
        let counted = countedSets(session.sets)
        var candidates: [RecordKind: RecordHolder] = [:]

        func offer(_ kind: RecordKind, key: [Double], set: CountedSet, value: Double, low: Bool = false) {
            let holder = RecordHolder(
                key: key,
                set: set,
                value: value,
                low: low,
                workoutID: session.workoutID,
                time: session.time
            )
            if let current = candidates[kind] {
                let wins = holder.low == current.low ? lexBetter(key, current.key) : !holder.low
                if wins { candidates[kind] = holder }
            } else {
                candidates[kind] = holder
            }
        }

        for set in counted {
            let kg = set.weightKg
            let reps = Double(set.reps)
            if set.reps > 0 {
                switch category {
                case .strength where kg > 0:
                    let estimate = e1rm(weight: kg, reps: set.reps, formula: options.formula)
                    offer(
                        .e1rm,
                        key: [estimate.value, kg, reps],
                        set: set,
                        value: estimate.value,
                        low: estimate.lowConfidence
                    )
                    offer(.heaviest, key: [kg, reps], set: set, value: kg)
                    offer(.bestVolumeSet, key: [kg * reps, kg], set: set, value: kg * reps)
                case .repBased where kg > 0:
                    offer(.heaviest, key: [kg, reps], set: set, value: kg)
                    offer(.bestVolumeSet, key: [kg * reps, kg], set: set, value: kg * reps)
                case .assisted:
                    offer(.heaviest, key: [-kg, reps], set: set, value: kg)
                default:
                    break
                }
            }
            // A duration counts whether or not the set also has reps (a plank logged as 1 rep, 60 s).
            if set.duration > 0 {
                offer(.longestDuration, key: [Double(set.duration)], set: set, value: Double(set.duration))
            }
        }

        var prs: [PersonalRecord] = []
        // Weight (kg) of the set that set the heaviest PR this session; its reps PR is suppressed.
        var heaviestKg: Double?
        for kind in [RecordKind.e1rm, .heaviest, .bestVolumeSet, .repsAtWeight, .longestDuration] {
            if kind == .repsAtWeight {
                if let pr = addReps(session, counted, skipping: heaviestKg) { prs.append(pr) }
                continue
            }
            guard let candidate = candidates[kind] else { continue }
            if let current = best[kind],
                !e1rmBeats(candidate.key[0], low: candidate.low, current.key[0], currentLow: current.low)
            {
                continue
            }
            best[kind] = candidate
            if kind == .heaviest { heaviestKg = candidate.set.weightKg }
            prs.append(personalRecord(kind, candidate))
        }
        return prs
    }

    private func personalRecord(_ kind: RecordKind, _ holder: RecordHolder) -> PersonalRecord {
        let weight = displayedWeight(holder.set, unit: options.displayUnit)
        let value: Double
        switch kind {
        case .e1rm, .bestVolumeSet: value = displayedAggregate(kg: holder.value, unit: options.displayUnit)
        case .heaviest: value = weight
        case .longestDuration, .repsAtWeight: value = holder.value
        }
        return PersonalRecord(kind: kind, value: value, weight: weight, reps: holder.set.reps)
    }

    /// A row at least as good in weight (at most, for assisted) and with at least as many reps.
    private func dominated(_ set: CountedSet) -> Bool {
        rows.contains { row in
            guard row.set.reps >= set.reps else { return false }
            let order = compareKg(row.set.weightKg, set.weightKg)
            return (inverted ? -order : order) >= 0
        }
    }

    /// Updates the reps-at-weight table. The session sets a reps PR when one of its per-weight bests is not dominated
    /// by the table so far; of those the heaviest (assisted: least assistance) is reported. The weight that set the
    /// heaviest PR this session (`skipping`) is never reported - a new heaviest weight has never been lifted, so one
    /// set would count as two PRs - but it still enters the table.
    private mutating func addReps(_ session: Session, _ counted: [CountedSet], skipping: Double?) -> PersonalRecord? {
        var perWeight: [CountedSet] = []
        for set in counted where set.reps > 0 {
            if let i = perWeight.firstIndex(where: { compareKg($0.weightKg, set.weightKg) == 0 }) {
                if set.reps > perWeight[i].reps { perWeight[i] = set }
            } else {
                perWeight.append(set)
            }
        }

        var pick: CountedSet?
        for set in perWeight {
            if let skipping, compareKg(set.weightKg, skipping) == 0 { continue }
            if dominated(set) { continue }
            guard let current = pick else {
                pick = set
                continue
            }
            let order = compareKg(set.weightKg, current.weightKg)
            if (inverted ? -order : order) > 0 { pick = set }
        }

        for set in perWeight {
            if let i = rows.firstIndex(where: { compareKg($0.set.weightKg, set.weightKg) == 0 }) {
                if set.reps > rows[i].set.reps {
                    rows[i] = RepsRow(set: set, workoutID: session.workoutID, time: session.time)
                }
            } else {
                rows.append(RepsRow(set: set, workoutID: session.workoutID, time: session.time))
            }
        }

        guard let pick else { return nil }
        return PersonalRecord(
            kind: .repsAtWeight,
            value: Double(pick.reps),
            weight: displayedWeight(pick, unit: options.displayUnit),
            reps: pick.reps
        )
    }
}

/// The records of one exercise, folded over all its sessions in time order (input order is irrelevant; when two
/// sessions tie the earlier one keeps the record). Rows are ordered `e1rm`, `heaviest`, `bestVolumeSet`,
/// `longestDuration`, then one `repsAtWeight` row per distinct weight (kg-equal within 1e-6): the most reps at it,
/// heaviest first (assisted: least assistance first). A record that no session can set is absent.
///
/// Applicability: e1RM and volume are strength-only (rep types count volume only with added weight); `heaviest` covers
/// strength, rep types with weight > 0, and assisted (inverted); `longestDuration` and `repsAtWeight` apply to all.
/// In-session ties: e1RM by heavier weight then reps; heaviest by reps; volume by heavier weight.
public nonisolated func records(_ sessions: [Session], weightType: WeightType, options: RecordsOptions)
    -> [ExerciseRecord]
{
    var tracker = RecordTracker(weightType: weightType, options: options)
    for session in sortedByTime(sessions) { _ = tracker.add(session) }
    let unit = options.displayUnit

    var out: [ExerciseRecord] = []
    for kind in [RecordKind.e1rm, .heaviest, .bestVolumeSet, .longestDuration] {
        guard let holder = tracker.best[kind] else { continue }
        let weight = displayedWeight(holder.set, unit: unit)
        let value: Double
        switch kind {
        case .e1rm, .bestVolumeSet: value = displayedAggregate(kg: holder.value, unit: unit)
        case .heaviest: value = weight
        default: value = holder.value
        }
        out.append(
            ExerciseRecord(
                kind: kind,
                value: value,
                weight: weight,
                reps: holder.set.reps,
                durationSeconds: holder.set.duration,
                workoutID: holder.workoutID,
                time: holder.time,
                lowConfidence: holder.low
            )
        )
    }

    let rows = tracker.rows.sorted {
        tracker.inverted ? $0.set.weightKg < $1.set.weightKg : $0.set.weightKg > $1.set.weightKg
    }
    for row in rows {
        out.append(
            ExerciseRecord(
                kind: .repsAtWeight,
                value: Double(row.set.reps),
                weight: displayedWeight(row.set, unit: unit),
                reps: row.set.reps,
                durationSeconds: row.set.duration,
                workoutID: row.workoutID,
                time: row.time
            )
        )
    }
    return out
}
