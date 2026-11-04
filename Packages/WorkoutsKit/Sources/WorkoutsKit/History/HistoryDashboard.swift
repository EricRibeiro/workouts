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
        guard limit > 0 else { return [] }
        let finished = workouts.filter { $0.finishedAt != nil }
        var names: [String: String] = [:]
        for workout in finished {
            for row in workout.exercises ?? [] {
                names["\(workout.id.uuidString).\(row.exerciseID.uuidString)"] = row.exerciseName
            }
        }

        var found: [RecentPR] = []
        for (exerciseID, sessions) in ExerciseBestSets.sessions(from: finished, weightType: weightType) {
            let type = sessions.first?.weightType ?? .weighted
            for (session, prs) in prsForEachSession(sessions, weightType: type, options: options) {
                guard let first = prs.first else { continue }
                let id = "\(session.workoutID.uuidString).\(exerciseID.uuidString)"
                found.append(
                    RecentPR(
                        workoutID: session.workoutID,
                        exerciseID: exerciseID,
                        exerciseName: names[id] ?? "Exercise",
                        date: session.time,
                        kind: first.kind,
                        text: text(for: first, unit: options.displayUnit),
                        recordCount: prs.count
                    )
                )
            }
        }
        found.sort { lhs, rhs in
            lhs.date != rhs.date ? lhs.date > rhs.date : lhs.exerciseName < rhs.exerciseName
        }
        // One row per session: a workout with the same exercise twice repeats the id, keep the first.
        var seen = Set<String>()
        return Array(found.filter { seen.insert($0.id).inserted }.prefix(limit))
    }

    /// The record's value as text.
    public static func text(for record: PersonalRecord, unit: WeightUnit) -> String {
        switch record.kind {
        case .e1rm:
            return "e1RM \(formatWeight(record.value)) \(unit.rawValue)"
        case .longestDuration:
            return formatSetDetail(
                weight: record.weight,
                unit: unit,
                reps: nil,
                durationSeconds: Int(record.value.rounded())
            )
        case .heaviest, .bestVolumeSet, .repsAtWeight:
            return formatSetDetail(weight: record.weight, unit: unit, reps: record.reps, durationSeconds: nil)
        }
    }
}
