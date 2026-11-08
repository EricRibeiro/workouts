import Foundation

/// The search scope of the History list: every finished workout, or only those that newly set a record.
public nonisolated enum HistoryScope: String, CaseIterable, Hashable, Sendable {
    case all
    case prs

    public var title: String {
        switch self {
        case .all: "All"
        case .prs: "PRs"
        }
    }
}

/// One finished workout as a History row (`docs/port/screens/history.md` section 2, "Card"). Everything is derived on
/// read from the workout; nothing here is stored.
public nonisolated struct HistoryEntry: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var startedAt: Date
    public var durationSeconds: Int
    /// Sum of weight x reps over counted sets, in `unit`, rounded to 0.5.
    public var volume: Double
    /// The same volume unrounded, in kg: sum these across workouts and round once (``displayedVolume(kg:displayUnit:)``).
    public var volumeKg: Double
    public var unit: WeightUnit
    /// Records the workout newly set, summed over its exercises, against sessions strictly before it.
    public var prCount: Int
    /// Names of the exercises in the workout, for search.
    public var exerciseNames: [String]

    public init(
        id: UUID,
        name: String,
        startedAt: Date,
        durationSeconds: Int,
        volume: Double,
        volumeKg: Double? = nil,
        unit: WeightUnit,
        prCount: Int,
        exerciseNames: [String]
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.volume = volume
        self.volumeKg = volumeKg ?? convert(volume, from: unit, to: .kg)
        self.unit = unit
        self.prCount = prCount
        self.exerciseNames = exerciseNames
    }
}

/// A month heading and its entries, newest first.
public nonisolated struct HistorySection: Identifiable, Hashable, Sendable {
    /// The first instant of the month in the grouping calendar.
    public var id: Date
    /// `November 2026`.
    public var title: String
    public var entries: [HistoryEntry]
}

/// The pure pieces of the History list: building entries from workouts, month grouping, search and the row texts.
public nonisolated enum HistoryList {
    // MARK: Building entries

    /// One entry per finished workout, newest first. Volume is in `options.displayUnit`, summed in kg and rounded once (as the Finish sheet does); the PR count compares each
    /// exercise session with the sessions of the same exercise strictly before the workout.
    @MainActor
    public static func entries(
        from workouts: [Workout],
        weightType: (UUID) -> WeightType?,
        options: RecordsOptions
    ) -> [HistoryEntry] {
        HistoryDashboard.build(from: workouts, weightType: weightType, options: options).entries
    }

    /// The entries from an already folded history (`HistoryDashboard.foldSessions`).
    static func entries(
        finished: [Workout],
        folded: [FoldedSession],
        options: RecordsOptions
    ) -> [HistoryEntry] {
        var prCounts: [UUID: Int] = [:]
        var volumes: [UUID: Double] = [:]
        for item in folded {
            prCounts[item.session.workoutID, default: 0] += item.prs.count
            volumes[item.session.workoutID, default: 0] += volumeKg(
                of: item.session.sets,
                weightType: item.session.weightType
            )
        }

        return finished.sorted { $0.startedAt > $1.startedAt }.map { workout in
            let rows = (workout.exercises ?? []).sorted { $0.position < $1.position }
            return HistoryEntry(
                id: workout.id,
                name: workout.name,
                startedAt: workout.startedAt,
                durationSeconds: duration(from: workout.startedAt, to: workout.finishedAt),
                volume: displayedVolume(kg: volumes[workout.id] ?? 0, displayUnit: options.displayUnit),
                volumeKg: volumes[workout.id] ?? 0,
                unit: options.displayUnit,
                prCount: prCounts[workout.id] ?? 0,
                exerciseNames: rows.map(\.exerciseName)
            )
        }
    }

    /// Whole seconds between start and finish; 0 when unfinished or the clock ran backwards.
    public static func duration(from start: Date, to end: Date?) -> Int {
        guard let end else { return 0 }
        return max(0, Int(end.timeIntervalSince(start).rounded()))
    }

    // MARK: Grouping and search

    /// Month `Section`s, newest first, cut in `calendar`'s time zone. Entries keep their order inside a month
    /// (newest first).
    public static func sections(_ entries: [HistoryEntry], calendar: Calendar = .current) -> [HistorySection] {
        var order: [Date] = []
        var groups: [Date: [HistoryEntry]] = [:]
        for entry in entries.sorted(by: { $0.startedAt > $1.startedAt }) {
            let month = monthStart(of: entry.startedAt, calendar: calendar)
            if groups[month] == nil { order.append(month) }
            groups[month, default: []].append(entry)
        }
        return order.map {
            HistorySection(id: $0, title: monthTitle($0, calendar: calendar), entries: groups[$0] ?? [])
        }
    }

    /// The first instant of the Gregorian month containing `date`, in `calendar`'s time zone.
    public static func monthStart(of date: Date, calendar: Calendar = .current) -> Date {
        let calendar = gregorian(like: calendar)
        return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// `November 2026`.
    public static func monthTitle(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(monthTitleStyle(in: calendar))
    }

    /// Entries in `scope` whose workout name or an exercise name contains `query` (case and diacritics ignored).
    /// An empty query matches everything.
    public static func filter(_ entries: [HistoryEntry], query: String, scope: HistoryScope) -> [HistoryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            if scope == .prs && entry.prCount == 0 { return false }
            if needle.isEmpty { return true }
            return entry.name.localizedStandardContains(needle)
                || entry.exerciseNames.contains { $0.localizedStandardContains(needle) }
        }
    }

    // MARK: Texts

    /// `Sunday, Nov 1`; the year (`Sunday, Nov 1, 2025`) only when it is not the year of `now`.
    public static func dateText(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let sameYear = gregorian(like: calendar).isDate(date, equalTo: now, toGranularity: .year)
        return date.formatted(sameYear ? dayStyle(in: calendar) : dayWithYearStyle(in: calendar))
    }

    /// `1h 12min`, `45min`, `<1min` (under a minute; also 0). A whole hour reads `1h 0min`.
    public static func durationText(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes < 1 { return "<1min" }
        if minutes < 60 { return "\(minutes)min" }
        return "\(minutes / 60)h \(minutes % 60)min"
    }

    /// `15,421 lb`: whole units with thousands separators.
    public static func volumeText(_ volume: Double, unit: WeightUnit) -> String {
        "\(volume.formatted(volumeStyle)) \(unit.rawValue)"
    }

    /// Whole units, thousands separators, halves rounded up (away from zero), always en_US. A `FormatStyle` is a Sendable
    /// value, so this one is shared by every row and by the background reader.
    private static let volumeStyle = FloatingPointFormatStyle<Double>.number
        .locale(Locale(identifier: "en_US"))
        .grouping(.automatic)
        .precision(.fractionLength(0))
        .rounded(rule: .toNearestOrAwayFromZero)

    /// `1 PR`, `3 PRs`.
    public static func prText(count: Int) -> String {
        count == 1 ? "1 PR" : "\(count) PRs"
    }

    /// The row's one VoiceOver label: `name, date, duration, volume, N PRs` (the PR part only when there is one).
    public static func accessibilityLabel(
        for entry: HistoryEntry,
        activeKcal: Double? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        var parts = [
            entry.name,
            dateText(entry.startedAt, now: now, calendar: calendar),
            durationText(seconds: entry.durationSeconds),
            volumeText(entry.volume, unit: entry.unit),
        ]
        if entry.prCount > 0 { parts.append(prText(count: entry.prCount)) }
        if let activeKcal { parts.append("\(FitnessFormat.wholeNumber(activeKcal)) active calories") }
        return parts.joined(separator: ", ")
    }

    // The date styles are verbatim patterns (`EEEE, MMM d`) in en_US; the grouping calendar and its time zone are applied
    // per call, since they follow the caller.
    private static let monthTitleFormat = Date.VerbatimFormatStyle(
        format: "\(month: .wide) \(year: .padded(4))",
        locale: Locale(identifier: "en_US"),
        timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
    )
    private static let dayFormat = Date.VerbatimFormatStyle(
        format: "\(weekday: .wide), \(month: .abbreviated) \(day: .defaultDigits)",
        locale: Locale(identifier: "en_US"),
        timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
    )
    private static let dayWithYearFormat = Date.VerbatimFormatStyle(
        format: "\(weekday: .wide), \(month: .abbreviated) \(day: .defaultDigits), \(year: .padded(4))",
        locale: Locale(identifier: "en_US"),
        timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
    )

    private static func monthTitleStyle(in calendar: Calendar) -> Date.VerbatimFormatStyle {
        applying(calendar, to: monthTitleFormat)
    }

    private static func dayStyle(in calendar: Calendar) -> Date.VerbatimFormatStyle {
        applying(calendar, to: dayFormat)
    }

    private static func dayWithYearStyle(in calendar: Calendar) -> Date.VerbatimFormatStyle {
        applying(calendar, to: dayWithYearFormat)
    }

    private static func applying(_ calendar: Calendar, to style: Date.VerbatimFormatStyle) -> Date.VerbatimFormatStyle {
        var style = style
        style.timeZone = calendar.timeZone
        return style
    }
}
