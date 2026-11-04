import Foundation

/// The numbers of the History dashboard's "This Week" card.
public nonisolated struct ThisWeekSummary: Hashable, Sendable {
    public var workouts: Int
    public var durationSeconds: Int
    public var volume: Double
    public var unit: WeightUnit

    public init(workouts: Int, durationSeconds: Int, volume: Double, unit: WeightUnit) {
        self.workouts = workouts
        self.durationSeconds = durationSeconds
        self.volume = volume
        self.unit = unit
    }
}

/// A record newly set in a finished workout, for the "Recent PRs" card: one per exercise session, showing its
/// first record (e1RM, heaviest, volume, reps, duration, in that order).
public nonisolated struct RecentPR: Identifiable, Hashable, Sendable {
    public var workoutID: UUID
    public var exerciseID: UUID
    public var exerciseName: String
    public var date: Date
    public var kind: RecordKind
    /// The value as text: `e1RM 120 kg`, `100 kg × 5`, `45 s`.
    public var text: String
    /// Records the session set in total (this one included).
    public var recordCount: Int

    public var id: String { "\(workoutID.uuidString).\(exerciseID.uuidString)" }

    public init(
        workoutID: UUID,
        exerciseID: UUID,
        exerciseName: String,
        date: Date,
        kind: RecordKind,
        text: String,
        recordCount: Int
    ) {
        self.workoutID = workoutID
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.date = date
        self.kind = kind
        self.text = text
        self.recordCount = recordCount
    }

    /// `Bench Press, e1RM 120 kg`, for VoiceOver.
    public var sentence: String { "\(exerciseName), \(text)" }
}

/// What the History tab shows, derived in one fold: the list rows and the "Recent PRs" card.
public nonisolated struct HistorySummary: Equatable, Sendable {
    public var entries: [HistoryEntry]
    public var recentPRs: [RecentPR]

    public init(entries: [HistoryEntry], recentPRs: [RecentPR]) {
        self.entries = entries
        self.recentPRs = recentPRs
    }
}

/// One exercise session with the records it newly set.
nonisolated struct FoldedSession {
    var exerciseID: UUID
    var session: Session
    var prs: [PersonalRecord]
}

/// The pure pieces of the History dashboard cards (`docs/port/screens/history.md` section 5).
public nonisolated enum HistoryDashboard {
    /// The workouts started in the Monday-first week containing `now` (cut in `calendar`'s time zone), with their
    /// total duration and volume. `unit` is the volume unit when no entry says (entries share the display unit).
    public static func thisWeek(
        entries: [HistoryEntry],
        calendar: Calendar,
        now: Date,
        unit: WeightUnit = .kg
    ) -> ThisWeekSummary {
        let calendar = mondayFirst(calendar)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let inWeek = entries.filter { entry in
            guard let week else { return false }
            return entry.startedAt >= week.start && entry.startedAt < week.end
        }
        return ThisWeekSummary(
            workouts: inWeek.count,
            durationSeconds: inWeek.reduce(0) { $0 + $1.durationSeconds },
            volume: round05(inWeek.reduce(0) { $0 + $1.volume }),
            unit: inWeek.first?.unit ?? entries.first?.unit ?? unit
        )
    }

    /// The newest entry by start date.
    public static func lastWorkout(entries: [HistoryEntry]) -> HistoryEntry? {
        entries.max { $0.startedAt < $1.startedAt }
    }

    /// The latest `limit` exercise sessions that newly set a record, newest first (ties by exercise name). Records
    /// are judged like the History rows: against the exercise's sessions strictly before.
    @MainActor
    public static func recentPRs(
        from workouts: [Workout],
        weightType: (UUID) -> WeightType?,
        options: RecordsOptions,
        limit: Int = 3
    ) -> [RecentPR] {
        build(from: workouts, weightType: weightType, options: options, limit: limit).recentPRs
    }

    /// Everything the History tab derives from its finished workouts, with the sessions and records folded once:
    /// the rows and the "Recent PRs" card. Equal to calling `HistoryList.entries` and ``recentPRs(from:weightType:options:limit:)``
    /// separately, in one pass.
    @MainActor
    public static func build(
        from workouts: [Workout],
        weightType: (UUID) -> WeightType?,
        options: RecordsOptions,
        limit: Int = 3
    ) -> HistorySummary {
        let finished = workouts.filter { $0.finishedAt != nil }
        let folded = foldSessions(finished, weightType: weightType, options: options)
        return HistorySummary(
            entries: HistoryList.entries(finished: finished, folded: folded, options: options),
            recentPRs: recentPRs(finished: finished, folded: folded, options: options, limit: limit)
        )
    }

    /// Every exercise's sessions with the records each newly set, one fold per exercise.
    @MainActor
    static func foldSessions(
        _ finished: [Workout],
        weightType: (UUID) -> WeightType?,
        options: RecordsOptions
    ) -> [FoldedSession] {
        var folded: [FoldedSession] = []
        for (exerciseID, sessions) in ExerciseBestSets.sessions(from: finished, weightType: weightType) {
            // One fold per exercise, oldest first, instead of refolding the earlier history for every session.
            let type = sessions.first?.weightType ?? .weighted
            for (session, prs) in prsForEachSession(sessions, weightType: type, options: options) {
                folded.append(FoldedSession(exerciseID: exerciseID, session: session, prs: prs))
            }
        }
        return folded
    }

    @MainActor
    static func recentPRs(
        finished: [Workout],
        folded: [FoldedSession],
        options: RecordsOptions,
        limit: Int
    ) -> [RecentPR] {
        guard limit > 0 else { return [] }
        var names: [String: String] = [:]
        for workout in finished {
            for row in workout.exercises ?? [] {
                names["\(workout.id.uuidString).\(row.exerciseID.uuidString)"] = row.exerciseName
            }
        }

        var found: [RecentPR] = []
        for item in folded {
            guard let first = item.prs.first else { continue }
            let id = "\(item.session.workoutID.uuidString).\(item.exerciseID.uuidString)"
            found.append(
                RecentPR(
                    workoutID: item.session.workoutID,
                    exerciseID: item.exerciseID,
                    exerciseName: names[id] ?? "Exercise",
                    date: item.session.time,
                    kind: first.kind,
                    text: text(for: first, unit: options.displayUnit),
                    recordCount: item.prs.count
                )
            )
        }
        found.sort { lhs, rhs in
            lhs.date != rhs.date ? lhs.date > rhs.date : lhs.exerciseName < rhs.exerciseName
        }
        // One row per session: a workout with the same exercise twice repeats the id, keep the first.
        var seen = Set<String>()
        return Array(found.filter { seen.insert($0.id).inserted }.prefix(limit))
    }

    /// The record's value as text, weights with thousands separators like the volume (`e1RM 1,929 lb`).
    public static func text(for record: PersonalRecord, unit: WeightUnit) -> String {
        switch record.kind {
        case .e1rm:
            return "e1RM \(groupedWeight(record.value)) \(unit.rawValue)"
        case .longestDuration:
            let load = record.weight > 0 ? "\(groupedWeight(record.weight)) \(unit.rawValue)" : nil
            let time = formatDuration(seconds: Int(record.value.rounded()))
            return load.map { "\($0) × \(time)" } ?? time
        case .heaviest, .bestVolumeSet, .repsAtWeight:
            let load = record.weight > 0 ? "\(groupedWeight(record.weight)) \(unit.rawValue)" : nil
            switch (load, record.reps > 0 ? record.reps : nil) {
            case (let load?, let reps?): return "\(load) × \(reps)"
            case (let load?, nil): return load
            case (nil, let reps?): return "\(reps) reps"
            case (nil, nil): return ""
            }
        }
    }

    /// A weight with thousands separators and up to two decimals, like `formatWeight` otherwise: `1,929`, `117.5`.
    public static func groupedWeight(_ weight: Double) -> String {
        let format = NumberFormatter()
        format.locale = Locale(identifier: "en_US")
        format.numberStyle = .decimal
        format.usesGroupingSeparator = true
        format.minimumFractionDigits = 0
        format.maximumFractionDigits = 2
        let text = format.string(from: NSNumber(value: weight)) ?? formatWeight(weight)
        return text == "-0" ? "0" : text
    }
}
