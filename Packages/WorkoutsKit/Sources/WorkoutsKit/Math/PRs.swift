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
            let before = tracker
            for session in ordered[start..<end] {
                var copy = before
                out.append((session, copy.add(session)))
            }
            for session in ordered[start..<end] { _ = tracker.add(session) }
        }
        start = end
    }
    return out
}
