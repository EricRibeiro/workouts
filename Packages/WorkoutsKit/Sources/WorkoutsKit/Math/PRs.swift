import Foundation

/// A record newly set by a session.
public nonisolated struct PersonalRecord: Hashable, Sendable {
    public var kind: RecordKind
    /// e1RM, weight, volume (display unit), seconds for `longestDuration`, reps for `repsAtWeight`.
    public var value: Double
    /// The setting set's weight in the display unit.
    public var weight: Double
    public var reps: Int

    public init(kind: RecordKind, value: Double, weight: Double, reps: Int) {
        self.kind = kind
        self.value = value
        self.weight = weight
        self.reps = reps
    }
}

/// The records `session` newly set against `history`, ordered e1RM, heaviest, volume, reps, duration.
///
/// - History: only entries strictly before `session.time`; an entry with the same workout and exercise ids as the
///   session is ignored. Pass every session of the exercise, in any order.
/// - "Equal is not a PR." The first session sets every record it can, except the reps PR of its heaviest set; a
///   session with only warm-ups or unchecked sets sets none.
/// - Reps PRs use dominance: a set is one only if no earlier set had at least that weight (at most, for assisted) and
///   at least those reps. A session counts once for this kind, for its heaviest qualifying set.
/// - "One set is not two PRs": the weight that set the heaviest PR in this session is skipped for the reps PR.
public nonisolated func prsInSession(
    history: [Session],
    session: Session,
    weightType: WeightType,
    options: RecordsOptions
) -> [PersonalRecord] {
    var tracker = RecordTracker(weightType: weightType, options: options)
    for entry in sortedByTime(history) {
        guard entry.time < session.time else { continue }
        if entry.workoutID == session.workoutID && entry.exerciseID == session.exerciseID { continue }
        _ = tracker.add(entry)
    }
    return tracker.add(session)
}

/// The records every session of one exercise newly set, in one pass: the same answer as calling ``prsInSession`` with
/// the whole list for each session, without refolding the history each time (O(n) instead of O(n^2)).
///
/// Ordered oldest first (ties keep input order). Sessions that share a start time never count toward each other, like
/// the "strictly before" rule of ``prsInSession``: each member of a tied run is evaluated on a copy of the tracker as
/// it stood before the run, then the run is folded in. (The same-workout-and-exercise skip of ``prsInSession`` is
/// subsumed: such sessions share a start time.)
nonisolated func prsForEachSession(
    _ sessions: [Session],
    weightType: WeightType,
    options: RecordsOptions
) -> [(session: Session, prs: [PersonalRecord])] {
    let ordered = sortedByTime(sessions)
    var tracker = RecordTracker(weightType: weightType, options: options)
    var out: [(session: Session, prs: [PersonalRecord])] = []
    out.reserveCapacity(ordered.count)

    var start = 0
    while start < ordered.count {
        var end = start + 1
        while end < ordered.count && ordered[end].time == ordered[start].time { end += 1 }
        if end - start == 1 {
            out.append((ordered[start], tracker.add(ordered[start])))
        } else {
            // Rows of one exercise in one workout are one session, as the Finish screen judges them: they are
            // scored together against the history before the run, and each record goes to the row holding its set.
            let run = Array(ordered[start..<end])
            let before = tracker
            var groups: [[Int]] = []
            var groupOf: [WorkoutExerciseKey: Int] = [:]
            for (index, session) in run.enumerated() {
                let key = WorkoutExerciseKey(workoutID: session.workoutID, exerciseID: session.exerciseID)
                if let group = groupOf[key] {
                    groups[group].append(index)
                } else {
                    groupOf[key] = groups.count
                    groups.append([index])
                }
            }
            var results = [[PersonalRecord]](repeating: [], count: run.count)
            for members in groups {
                var copy = before
                if members.count == 1 {
                    results[members[0]] = copy.add(run[members[0]])
                } else {
                    let rows = members.map { run[$0] }
                    let split = splitRecords(copy.add(mergedSession(rows)), among: rows, options: options)
                    for (member, prs) in zip(members, split) { results[member] = prs }
                }
            }
            for (session, prs) in zip(run, results) { out.append((session, prs)) }
            for members in groups {
                _ = tracker.add(members.count == 1 ? run[members[0]] : mergedSession(members.map { run[$0] }))
            }
        }
        start = end
    }
    return out
}

private nonisolated struct WorkoutExerciseKey: Hashable {
    var workoutID: UUID
    var exerciseID: UUID
}

/// The rows of one exercise in one workout as a single session (sets concatenated in row order), the way the Finish
/// screen judges them.
nonisolated func mergedSession(_ rows: [Session]) -> Session {
    guard var merged = rows.first else {
        return Session(workoutID: UUID(), time: .distantPast, exerciseID: UUID(), weightType: .weighted, sets: [])
    }
    merged.sets = rows.flatMap(\.sets)
    return merged
}

/// Hands each record of a merged session to the first row that holds a matching counted set (same displayed weight and
/// reps, or the duration), else to the first row, so the per-row counts add up to `prs.count`.
nonisolated func splitRecords(
    _ prs: [PersonalRecord],
    among rows: [Session],
    options: RecordsOptions
) -> [[PersonalRecord]] {
    var out = [[PersonalRecord]](repeating: [], count: rows.count)
    let counted = rows.map { countedSets($0.sets) }
    for pr in prs {
        let owner = counted.firstIndex { sets in
            sets.contains { candidate in
                if pr.kind == .longestDuration { return candidate.duration == Int(pr.value) }
                return candidate.reps == pr.reps && displayedWeight(candidate, unit: options.displayUnit) == pr.weight
            }
        }
        out[owner ?? 0].append(pr)
    }
    return out
}

/// The records the rows of one exercise in one workout newly set against `history`, per row. Same total as
/// ``prsInSession`` over the rows merged into one session (what the Finish screen shows); `history` entries of this
/// workout are ignored.
nonisolated func prsInWorkout(
    history: [Session],
    rows: [Session],
    weightType: WeightType,
    options: RecordsOptions
) -> [[PersonalRecord]] {
    guard rows.count > 1 else {
        return rows.map { prsInSession(history: history, session: $0, weightType: weightType, options: options) }
    }
    let merged = prsInSession(history: history, session: mergedSession(rows), weightType: weightType, options: options)
    return splitRecords(merged, among: rows, options: options)
}
