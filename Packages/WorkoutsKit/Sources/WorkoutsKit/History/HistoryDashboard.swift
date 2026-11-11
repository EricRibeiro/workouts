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

/// The mean of the same stretch of the weeks before this one: what a week in progress is compared against.
public nonisolated struct WeekToDate: Hashable, Sendable {
    public var volume: Double
    public var durationSeconds: Int
    public var workouts: Double
    /// How many earlier weeks the means cover, 1 up to the window.
    public var weeks: Int

    public init(volume: Double, durationSeconds: Int, workouts: Double, weeks: Int) {
        self.volume = volume
        self.durationSeconds = durationSeconds
        self.workouts = workouts
        self.weeks = weeks
    }
}

/// The weekly volume chart's y axis: `top` is `step` times the number of steps, and `ticks` run from 0 to `top`.
public nonisolated struct VolumeAxis: Hashable, Sendable {
    public var top: Double
    public var step: Double
    public var ticks: [Double]

    public init(top: Double, step: Double, ticks: [Double]) {
        self.top = top
        self.step = step
        self.ticks = ticks
    }

    /// Every `every`-th tick counted down from the top, oldest (lowest) first, so the top is always kept.
    public func thinned(every: Int) -> [Double] {
        guard every > 1 else { return ticks }
        return stride(from: ticks.count - 1, through: 0, by: -every).reversed().map { ticks[$0] }
    }
}

/// What the "This Week" hero card prints and speaks.
public nonisolated struct ThisWeekText: Hashable, Sendable {
    /// `1`: the workouts done this week.
    public var countText: String
    /// `of 3 workouts`, `of 1 workout`.
    public var goalText: String
    public var volumeText: String
    /// `0min` for an empty week.
    public var durationText: String
    /// The to-date volume mean in the same format; nil without a baseline or when it is zero.
    public var usualVolumeText: String?
    public var usualDurationText: String?
    /// The VoiceOver sentence, without any Fitness tail.
    public var spoken: String

    public init(
        countText: String,
        goalText: String,
        volumeText: String,
        durationText: String,
        usualVolumeText: String?,
        usualDurationText: String?,
        spoken: String
    ) {
        self.countText = countText
        self.goalText = goalText
        self.volumeText = volumeText
        self.durationText = durationText
        self.usualVolumeText = usualVolumeText
        self.usualDurationText = usualDurationText
        self.spoken = spoken
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

    /// The mean of the same stretch of each of the up-to-`window` Monday-first weeks before the current one: the entries
    /// that started between that week's Monday and the same weekday and time of day as `now` has in the current week, so
    /// a Monday morning is compared with earlier Monday mornings and not with whole weeks. Only weeks from the week of the
    /// first-ever workout on count (a week skipped inside that range counts as zero). Nil in the first week of use, when
    /// no earlier week exists, and for a `window` of 0 or less. Volume is rounded like ``ThisWeekSummary/volume``.
    public static func toDateBaseline(
        entries: [HistoryEntry],
        calendar: Calendar,
        now: Date,
        window: Int = 4
    ) -> WeekToDate? {
        let calendar = mondayFirst(calendar)
        guard window > 0, let first = entries.map(\.startedAt).min(),
            let firstWeek = calendar.dateInterval(of: .weekOfYear, for: first)?.start,
            let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        else { return nil }
        // Whole days then the wall-clock time of day, so a 23-hour or 25-hour DST day still lands on the same clock time.
        let days = calendar.dateComponents([.day], from: currentWeek, to: calendar.startOfDay(for: now)).day ?? 0
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        var sums = (workouts: 0, seconds: 0, kg: 0.0)
        var weeks = 0
        for back in 1...window {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: currentWeek), start >= firstWeek,
                let next = calendar.date(byAdding: .weekOfYear, value: 1, to: start),
                let day = calendar.date(byAdding: .day, value: days, to: start),
                let reached = calendar.date(
                    bySettingHour: time.hour ?? 0,
                    minute: time.minute ?? 0,
                    second: time.second ?? 0,
                    of: day
                )
            else { break }
            let end = min(reached, next)
            weeks += 1
            for entry in entries where entry.startedAt >= start && entry.startedAt <= end {
                sums.workouts += 1
                sums.seconds += entry.durationSeconds
                sums.kg += entry.volumeKg
            }
        }
        guard weeks > 0 else { return nil }
        let count = Double(weeks)
        return WeekToDate(
            volume: displayedVolume(kg: sums.kg / count, displayUnit: entries.first?.unit ?? .kg),
            durationSeconds: Int((Double(sums.seconds) / count).rounded()),
            workouts: Double(sums.workouts) / count,
            weeks: weeks
        )
    }

    /// The weekly volume chart's axis: 3 to 5 equal steps of 1, 2, 2.5 or 5 times a power of ten whose top is the smallest
    /// that reaches the highest bar or average (a tie goes to the step count nearest 4), so there are always 4 to 6 ticks.
    /// A step is never below 1 and 2.5 times a power of ten only appears from a step of 25 up, so every tick prints
    /// distinctly through ``HistoryList/compactVolumeText(_:)``. All-zero data gives top 1 and ticks `[0, 1]`.
    public static func volumeAxis(totals: [WeekTotal], averages: [Double?]) -> VolumeAxis {
        let highest = (totals.map(\.volume) + averages.compactMap { $0 }).filter(\.isFinite).max() ?? 0
        guard highest > 0 else { return VolumeAxis(top: 1, step: 1, ticks: [0, 1]) }
        let magnitude = floor(log10(highest))
        var best: (top: Double, step: Double, count: Int)?
        for exponent in Int(magnitude) - 1...Int(magnitude) + 1 {
            for base in [1.0, 2, 2.5, 5] {
                let step = base * pow(10, Double(exponent))
                guard step >= 1, base != 2.5 || step >= 10 else { continue }
                for count in 3...5 {
                    let top = step * Double(count)
                    guard top >= highest * (1 - 1e-9) else { continue }
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
        guard let best else { return VolumeAxis(top: 1, step: 1, ticks: [0, 1]) }
        return VolumeAxis(
            top: best.top,
            step: best.step,
            ticks: (0...best.count).map { Double($0) * best.step }
        )
    }

    /// The hero card's text: the count against the goal, the week's volume and time, what is usual by now, and the
    /// VoiceOver sentence (the Fitness calories and heart rate are left for the view to append).
    public static func heroText(week: ThisWeekSummary, goal: Int, toDate: WeekToDate?) -> ThisWeekText {
        let workouts = goal == 1 ? "workout" : "workouts"
        let volume = HistoryList.volumeText(week.volume, unit: week.unit)
        let duration = week.workouts == 0 ? "0min" : HistoryList.durationText(seconds: week.durationSeconds)
        let usualVolume = toDate.flatMap { $0.volume > 0 ? HistoryList.volumeText($0.volume, unit: week.unit) : nil }
        let usualDuration = toDate.flatMap {
            $0.durationSeconds > 0 ? HistoryList.durationText(seconds: $0.durationSeconds) : nil
        }

        var spoken = "This week, \(week.workouts) of \(goal) \(workouts)"
        if week.workouts > 0 {
            spoken += ", " + FitnessFormat.spokenDuration(seconds: TimeInterval(week.durationSeconds))
            if week.volume > 0 { spoken += ", " + volume }
        }
        if let toDate {
            var usual: [String] = []
            if let usualVolume { usual.append(usualVolume) }
            if toDate.durationSeconds > 0 {
                let minutes = (toDate.durationSeconds + 30) / 60 * 60
                usual.append(FitnessFormat.spokenDuration(seconds: TimeInterval(max(minutes, 60))))
            }
            if !usual.isEmpty { spoken += ", usually " + usual.joined(separator: " and ") + " by now" }
        }
        return ThisWeekText(
            countText: "\(week.workouts)",
            goalText: "of \(goal) \(workouts)",
            volumeText: volume,
            durationText: duration,
            usualVolumeText: usualVolume,
            usualDurationText: usualDuration,
            spoken: spoken
        )
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
