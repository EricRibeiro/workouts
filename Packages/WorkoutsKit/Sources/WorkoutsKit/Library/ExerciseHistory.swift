import Foundation

/// One completed set in the exercise detail's History segment.
public nonisolated struct ExerciseHistorySet: Hashable, Sendable, Identifiable {
    /// Position among the session's completed sets.
    public var id: Int
    public var kind: SetKind
    /// The set label: `W`, `D` or `F` for a marker, else the 1-based position among the session's completed sets (markers
    /// consume numbers, as in the workout detail: W, W, 3, 4).
    public var label: String
    /// Weight, reps or time as entered, in the set's own unit: `100 kg × 5`, `12 reps`, `45 s`.
    public var text: String
    /// True when this set set a personal record in its session.
    public var isPR: Bool

    public init(id: Int, kind: SetKind, label: String, text: String, isPR: Bool) {
        self.id = id
        self.kind = kind
        self.label = label
        self.text = text
        self.isPR = isPR
    }
}

/// One session (one exercise in one workout) in the History segment.
public nonisolated struct ExerciseHistorySession: Hashable, Sendable, Identifiable {
    /// The workout id; `<workout id>-2`, `-3`, ... when the exercise appears more than once in a workout.
    public var id: String
    public var workoutID: UUID
    public var workoutName: String
    public var time: Date
    public var sets: [ExerciseHistorySet]
    /// The records the session newly set (shown as a trophy and count when above zero).
    public var prCount: Int

    public init(
        id: String,
        workoutID: UUID,
        workoutName: String,
        time: Date,
        sets: [ExerciseHistorySet],
        prCount: Int
    ) {
        self.id = id
        self.workoutID = workoutID
        self.workoutName = workoutName
        self.time = time
        self.sets = sets
        self.prCount = prCount
    }
}

/// The History segment of the exercise detail (`docs/port/screens/exercises.md` section 2, "History tab").
public nonisolated enum ExerciseHistory {
    /// Sessions newest first, completed sets only (warm-ups included, marked `W`), weights as entered. A session with
    /// no completed set is left out. `names` resolves a workout id to its name; unknown or empty names read `Workout`.
    public static func sessions(
        _ sessions: [Session],
        names: [UUID: String],
        weightType: WeightType,
        options: RecordsOptions
    ) -> [ExerciseHistorySession] {
        let completed = sessions.map { session -> Session in
            var copy = session
            copy.sets = session.sets.filter(\.completed)
            return copy
        }
        var seen: [UUID: Int] = [:]
        var out: [ExerciseHistorySession] = []
        for (session, prs) in prsForEachSession(completed, weightType: weightType, options: options) {
            guard !session.sets.isEmpty else { continue }
            seen[session.workoutID, default: 0] += 1
            let occurrence = seen[session.workoutID] ?? 1
            let name = names[session.workoutID].flatMap { $0.isEmpty ? nil : $0 } ?? "Workout"
            let base = session.workoutID.uuidString
            out.append(
                ExerciseHistorySession(
                    id: occurrence == 1 ? base : "\(base)-\(occurrence)",
                    workoutID: session.workoutID,
                    workoutName: name,
                    time: session.time,
                    sets: setRows(session, prs: prs, displayUnit: options.displayUnit),
                    prCount: prs.count
                )
            )
        }
        return out.reversed()
    }

    private static func setRows(
        _ session: Session,
        prs: [PersonalRecord],
        displayUnit: WeightUnit
    ) -> [ExerciseHistorySet] {
        // Each record marks the first counted set that matches it (same displayed weight and reps, or the duration).
        var marked = Set<Int>()
        let counted = countedSets(session.sets)
        for pr in prs {
            let match = counted.first { candidate in
                if pr.kind == .longestDuration { return candidate.duration == Int(pr.value) }
                return candidate.reps == pr.reps && displayedWeight(candidate, unit: displayUnit) == pr.weight
            }
            if let match { marked.insert(match.index) }
        }
        return session.sets.enumerated().map { index, set in
            let text = formatSetDetail(
                weight: set.weight,
                unit: set.unit,
                reps: set.reps,
                durationSeconds: set.durationSeconds
            )
            return ExerciseHistorySet(
                id: index,
                kind: set.kind,
                label: SetInputFormat.setLabel(number: index + 1, kind: set.kind),
                text: text.isEmpty ? "–" : text,
                isPR: marked.contains(index)
            )
        }
    }
}
