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

/// Everything finished workouts did in one Monday-first week: the bars of the weekly volume chart.
public nonisolated struct WeekTotal: Hashable, Sendable {
    /// Start of the Monday, in the calendar's time zone.
    public var weekStart: Date
    public var workouts: Int
    public var durationSeconds: Int
    /// Total volume in the entries' display unit, rounded once to 0.5 like ``ThisWeekSummary/volume``.
    public var volume: Double

    public init(weekStart: Date, workouts: Int, durationSeconds: Int, volume: Double) {
        self.weekStart = weekStart
        self.workouts = workouts
        self.durationSeconds = durationSeconds
        self.volume = volume
    }
}

/// The mean week before the current one: what "this week" is compared against.
public nonisolated struct WeekBaseline: Hashable, Sendable {
    public var volume: Double
    public var durationSeconds: Int
    public var workouts: Double

    public init(volume: Double, durationSeconds: Int, workouts: Double) {
        self.volume = volume
        self.durationSeconds = durationSeconds
        self.workouts = workouts
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
        let weekUnit = inWeek.first?.unit ?? entries.first?.unit ?? unit
        return ThisWeekSummary(
            workouts: inWeek.count,
            durationSeconds: inWeek.reduce(0) { $0 + $1.durationSeconds },
            // Sum the unrounded kg and round once, so the total does not drift by up to 0.25 per workout.
            volume: displayedVolume(kg: inWeek.reduce(0) { $0 + $1.volumeKg }, displayUnit: weekUnit),
            unit: weekUnit
        )
    }

    /// The last `weeks` Monday-first weeks ending with the one containing `now`, oldest first and zero-filled, with each
    /// week's workouts, duration and volume. Weeks are cut like ``weeklyCounts(workouts:calendar:weeks:now:)``. Volume is
    /// the unrounded kg summed and rounded once, in the first entry's unit (entries share the display unit; kg when empty).
    public static func weeklyTotals(
        entries: [HistoryEntry],
        weeks: Int,
        calendar: Calendar,
        now: Date
    ) -> [WeekTotal] {
        let calendar = mondayFirst(calendar)
        let starts = weekStarts(weeks: weeks, calendar: calendar, now: now)
        let unit = entries.first?.unit ?? .kg
        var sums: [Date: (workouts: Int, seconds: Int, kg: Double)] = [:]
        for entry in entries {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: entry.startedAt)?.start else { continue }
            var sum = sums[start] ?? (0, 0, 0)
            sum.workouts += 1
            sum.seconds += entry.durationSeconds
            sum.kg += entry.volumeKg
            sums[start] = sum
        }
        return starts.map { start in
            let sum = sums[start] ?? (0, 0, 0)
            return WeekTotal(
                weekStart: start,
                workouts: sum.workouts,
                durationSeconds: sum.seconds,
                volume: displayedVolume(kg: sum.kg, displayUnit: unit)
            )
        }
    }

    /// For each value, the mean of the `window` values before it; nil while fewer than `window` precede it. The value
    /// itself is left out, so a week in progress never drags its own baseline. A `window` of 0 or less gives all nil.
    public static func trailingAverages(_ values: [Double], window: Int) -> [Double?] {
        values.indices.map { index in
            guard window > 0, index >= window else { return nil }
            return values[(index - window)..<index].reduce(0, +) / Double(window)
        }
    }

    /// The mean week among the `window` weeks before the last of `totals` (the current week); nil when fewer than
    /// `window` weeks precede it or when those weeks hold no workouts.
    public static func baseline(totals: [WeekTotal], window: Int = 4) -> WeekBaseline? {
        guard window > 0, totals.count > window else { return nil }
        let previous = totals[(totals.count - 1 - window)..<(totals.count - 1)]
        let workouts = previous.reduce(0) { $0 + $1.workouts }
        guard workouts > 0 else { return nil }
        let count = Double(window)
        let seconds = Double(previous.reduce(0) { $0 + $1.durationSeconds })
        return WeekBaseline(
            volume: previous.reduce(0) { $0 + $1.volume } / count,
            durationSeconds: Int((seconds / count).rounded()),
            workouts: Double(workouts) / count
        )
    }

    /// The top of the volume chart's y axis: 3 to 5 equal steps of 1, 2, 2.5 or 5 times a power of ten, the combination
    /// whose top is the smallest value that reaches the busiest week (a tie goes to the count nearest 4); 1 when every
    /// week is zero.
    public static func volumeAxisTop(totals: [WeekTotal]) -> Double {
        volumeAxis(totals: totals).top
    }

    /// The distance between the volume chart's gridlines: `volumeAxisTop` divided into 3 to 5 equal steps; 1 when every
    /// week is zero.
    public static func volumeAxisStep(totals: [WeekTotal]) -> Double {
        volumeAxis(totals: totals).step
    }

    private static func volumeAxis(totals: [WeekTotal]) -> (top: Double, step: Double) {
        let busiest = totals.map(\.volume).max() ?? 0
        guard busiest > 0, busiest.isFinite else { return (1, 1) }
        let magnitude = pow(10, floor(log10(busiest)))
        var best: (top: Double, step: Double, count: Int)?
        // Steps from a tenth of the busiest week's magnitude to ten times it cover every 3 to 5 step axis that can reach it.
        for exponent in -1...1 {
            for base in [1.0, 2, 2.5, 5] {
                let step = base * magnitude * pow(10, Double(exponent))
                for count in 3...5 {
                    let top = step * Double(count)
                    guard top >= busiest * (1 - 1e-9) else { continue }
                    let tolerance = top * 1e-9
                    if let current = best {
                        if top > current.top + tolerance { continue }
                        let closer = abs(count - 4) < abs(current.count - 4)
                        if top >= current.top - tolerance && !closer { continue }
                    }
                    best = (top, step, count)
                }
            }
        }
        guard let best else { return (1, 1) }
        return (best.top, best.step)
    }

    /// Active calories (from Apple Fitness) summed over the finished `workouts` started in the Monday-first week containing
    /// `now`; nil when none of them has any, so the dashboard can hide the figure.
    @MainActor
    public static func weekActiveCalories(
        workouts: [Workout],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Double? {
        let calendar = mondayFirst(calendar)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
        let values = workouts.compactMap { workout -> Double? in
            guard workout.isFinished, workout.startedAt >= week.start, workout.startedAt < week.end else {
                return nil
            }
            return workout.activeEnergyKcal
        }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    /// The average heart rate (from Apple Fitness) of the finished `workouts` started in the Monday-first week containing
    /// `now`, weighted by each workout's duration and counting only workouts that have an average; nil when none does.
    @MainActor
    public static func weekAverageHeartRate(
        workouts: [Workout],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Double? {
        let calendar = mondayFirst(calendar)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
        var weighted = 0.0
        var seconds = 0.0
        var plain = (sum: 0.0, count: 0)
        for workout in workouts {
            guard let end = workout.finishedAt, workout.startedAt >= week.start, workout.startedAt < week.end,
                let bpm = workout.avgHeartRate
            else { continue }
            let duration = max(0, end.timeIntervalSince(workout.startedAt))
            weighted += bpm * duration
            seconds += duration
            plain.sum += bpm
            plain.count += 1
        }
        if seconds > 0 { return weighted / seconds }
        // Zero-length workouts carry no weight; fall back to the plain mean rather than hiding the figure.
        return plain.count == 0 ? nil : plain.sum / Double(plain.count)
    }

    /// `128 bpm`: a heart rate as whole beats per minute.
    public static func heartRateText(_ bpm: Double) -> String {
        "\(FitnessFormat.wholeNumber(bpm)) bpm"
    }

    /// `128 beats per minute average`, for VoiceOver.
    public static func heartRateSpoken(_ bpm: Double) -> String {
        "\(FitnessFormat.wholeNumber(bpm)) beats per minute average"
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
    public static func build(
        from workouts: [Workout],
        weightType: (UUID) -> WeightType?,
        options: RecordsOptions,
        limit: Int = 3
    ) -> HistorySummary {
        let finished = workouts.filter(\.isFinished)
        let folded = foldSessions(finished, weightType: weightType, options: options)
        return HistorySummary(
            entries: HistoryList.entries(finished: finished, folded: folded, options: options),
            recentPRs: recentPRs(finished: finished, folded: folded, options: options, limit: limit)
        )
    }

    /// Every exercise's sessions with the records each newly set, one fold per exercise.
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
            return "e1RM \(WeightFormat.groupedText(record.value, unit: unit))"
        case .longestDuration:
            let load = record.weight > 0 ? WeightFormat.groupedText(record.weight, unit: unit) : nil
            let time = ClockFormat.compact(seconds: Int(record.value.rounded()))
            return load.map { "\($0) × \(time)" } ?? time
        case .heaviest, .bestVolumeSet, .repsAtWeight:
            let load = record.weight > 0 ? WeightFormat.groupedText(record.weight, unit: unit) : nil
            switch (load, record.reps > 0 ? record.reps : nil) {
            case (let load?, let reps?): return "\(load) × \(reps)"
            case (let load?, nil): return load
            case (nil, let reps?): return "\(reps) \(reps == 1 ? "rep" : "reps")"
            case (nil, nil): return ""
            }
        }
    }
}
