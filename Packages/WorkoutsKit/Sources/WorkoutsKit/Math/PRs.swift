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
