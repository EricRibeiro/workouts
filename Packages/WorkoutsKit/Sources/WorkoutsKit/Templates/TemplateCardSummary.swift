import Foundation

/// What a template card shows (`workout.md` sections 2 and 3): the exercise count, the first few exercise names with
/// their superset group, and when the template was last performed. Pure over the models; the views only lay it out.
public struct TemplateCardSummary: Sendable, Equatable {
    /// One exercise line: the exercise's name alone, plus its working sets as a short trailing text.
    public struct Line: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let text: String
        public let supersetGroup: Int?
        /// The working sets (warm-ups excluded): `4 × 8` for equal planned reps, `3 × 45 s` for equal planned
        /// durations, else `4 sets` (`1 set`); nil when the exercise has no working sets.
        public let detail: String?
        /// `detail` as VoiceOver reads it: `4 sets of 8 reps`, `3 sets of 45 seconds`, `4 sets`; nil without working sets.
        public let spokenDetail: String?
    }

    /// One entry of the card's VoiceOver custom content: the exercise name and its sets, or the overflow.
    public struct AccessibilityEntry: Sendable, Equatable {
        public let label: String
        public let value: String
    }

    public let exerciseCount: Int
    /// The first `maxLines` exercises in template order.
    public let lines: [Line]
    /// Exercises beyond `lines`.
    public let overflow: Int
    /// `Today`, `Yesterday`, `5 days ago`, `3 weeks ago` or a date; nil when the template was never performed.
    public let lastPerformed: String?
    /// How long that last session took (`52min`); nil when the template was never performed or the session has no
    /// measurable length (finish at or before start).
    public let lastDurationText: String?
    private let lastDurationSeconds: Int?

    /// `7 exercises`, `1 exercise`, `No exercises`.
    public var countText: String {
        switch exerciseCount {
        case 0: "No exercises"
        case 1: "1 exercise"
        default: "\(exerciseCount) exercises"
        }
    }

    /// `+ 3 more`, nil when everything fits.
    public var overflowText: String? { overflow > 0 ? "+ \(overflow) more" : nil }

    /// What VoiceOver reads on demand beyond the card's label (the custom-content rotor): one entry per shown line, the
    /// exercise name with its sets (`No sets` when it has none), then `And 2 more` when exercises are folded away.
    public var accessibilityEntries: [AccessibilityEntry] {
        var entries = lines.map { AccessibilityEntry(label: $0.text, value: $0.spokenDetail ?? "No sets") }
        if overflow > 0 { entries.append(AccessibilityEntry(label: "And \(overflow) more", value: "exercises")) }
        return entries
    }

    /// The card's one VoiceOver sentence: `name, 7 exercises, last done 5 days ago, last session 52 minutes` (the last
    /// parts only when known).
    public func accessibilityLabel(name: String) -> String {
        var parts = [name, countText]
        if let lastPerformed { parts.append("last done \(lastPerformed.lowercasedWord)") }
        if let lastDurationSeconds {
            parts.append("last session \(FitnessFormat.spokenDuration(seconds: TimeInterval(lastDurationSeconds)))")
        }
        return parts.joined(separator: ", ")
    }

    /// When each template was last performed and how long that session took, built in one pass over the finished
    /// workouts so a screen full of cards costs one scan (and one relationship read per workout) instead of one per card.
    /// The rule: the newest start among finished workouts done from the template, else among those with the same name
    /// (case-insensitive; imported history is not linked). In-progress workouts never count.
    public nonisolated struct LastPerformedIndex: Sendable, Equatable {
        private struct Entry: Sendable, Equatable {
            let started: Date
            let durationSeconds: Int?
        }

        private var byTemplate: [UUID: Entry] = [:]
        private var byName: [String: Entry] = [:]

        public init() {}

        public init(finishedWorkouts: [Workout]) {
            for workout in finishedWorkouts where !workout.isGone && workout.isFinished {
                let seconds = HistoryList.duration(from: workout.startedAt, to: workout.finishedAt)
                let entry = Entry(started: workout.startedAt, durationSeconds: seconds > 0 ? seconds : nil)
                if let linked = workout.template, !linked.isGone {
                    let id = linked.id
                    if byTemplate[id].map({ entry.started > $0.started }) ?? true { byTemplate[id] = entry }
                }
                let name = Self.key(workout.name)
                if byName[name].map({ entry.started > $0.started }) ?? true { byName[name] = entry }
            }
        }

        /// The newest linked start, else the newest same-name start; nil when never performed.
        public func lastPerformed(of template: Template) -> Date? { entry(of: template)?.started }

        /// Whole seconds the session behind `lastPerformed(of:)` took; nil when never performed or when it has no
        /// measurable length (finish at or before start).
        public func lastDurationSeconds(of template: Template) -> Int? { entry(of: template)?.durationSeconds }

        private func entry(of template: Template) -> Entry? {
            guard !template.isGone else { return nil }
            return byTemplate[template.id] ?? byName[Self.key(template.name)]
        }

        private static func key(_ name: String) -> String { name.lowercased() }
    }

    /// Summarises `template` with a prebuilt `index` (see `LastPerformedIndex`). A deleted template (a card SwiftUI
    /// re-evaluates once more after its folder or itself was deleted) summarises as empty: no lines, never performed;
    /// a deleted exercise is skipped and a deleted set does not count. A superset bar is kept on a line only
    /// when at least two members of its group are among the lines: a partner folded into "+ N more" leaves a lone bar
    /// that marks nothing.
    public static func make(
        for template: Template,
        index: LastPerformedIndex,
        maxLines: Int = 4,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TemplateCardSummary {
        guard !template.isGone else {
            return TemplateCardSummary(
                exerciseCount: 0,
                lines: [],
                overflow: 0,
                lastPerformed: nil,
                lastDurationText: nil,
                lastDurationSeconds: nil
            )
        }
        let exercises = (template.exercises ?? []).filter { !$0.isGone }.sorted {
            $0.position != $1.position ? $0.position < $1.position : $0.id.uuidString < $1.id.uuidString
        }
        let shown = exercises.prefix(max(0, maxLines))
        var groupSizes: [Int: Int] = [:]
        for exercise in shown {
            if let group = exercise.supersetGroup { groupSizes[group, default: 0] += 1 }
        }
        let lines = shown.map { exercise in
            Line(
                id: exercise.id,
                text: exercise.exerciseName,
                supersetGroup: exercise.supersetGroup.flatMap { (groupSizes[$0] ?? 0) >= 2 ? $0 : nil },
                detail: setsText(exercise.sets ?? []),
                spokenDetail: spokenSetsText(exercise.sets ?? [])
            )
        }
        let lastDurationSeconds = index.lastDurationSeconds(of: template)
        return TemplateCardSummary(
            exerciseCount: exercises.count,
            lines: lines,
            overflow: max(0, exercises.count - lines.count),
            lastPerformed: index.lastPerformed(of: template).map { relativeText($0, now: now, calendar: calendar) },
            lastDurationText: lastDurationSeconds.map { HistoryList.durationText(seconds: $0) },
            lastDurationSeconds: lastDurationSeconds
        )
    }

    /// `4 × 8` (equal planned reps), `3 × 45 s` (equal planned durations), `4 sets` / `1 set` otherwise; nil without
    /// working sets.
    static func setsText(_ sets: [TemplateSet]) -> String? {
        let working = sets.filter { !$0.isGone && $0.kind != .warmup }
        guard let first = working.first else { return nil }
        let count = working.count
        if let reps = first.reps, working.allSatisfy({ $0.reps == reps }) { return "\(count) × \(reps)" }
        if let seconds = first.durationSeconds, working.allSatisfy({ $0.durationSeconds == seconds }) {
            return "\(count) × \(ClockFormat.compact(seconds: seconds))"
        }
        return count == 1 ? "1 set" : "\(count) sets"
    }

    /// `setsText` as it is spoken: `4 sets of 8 reps`, `3 sets of 45 seconds`, `4 sets` / `1 set` otherwise; nil without
    /// working sets.
    static func spokenSetsText(_ sets: [TemplateSet]) -> String? {
        let working = sets.filter { !$0.isGone && $0.kind != .warmup }
        guard let first = working.first else { return nil }
        let count = working.count
        let noun = count == 1 ? "1 set" : "\(count) sets"
        if let reps = first.reps, working.allSatisfy({ $0.reps == reps }) {
            return "\(noun) of \(reps) \(reps == 1 ? "rep" : "reps")"
        }
        if let seconds = first.durationSeconds, working.allSatisfy({ $0.durationSeconds == seconds }) {
            return "\(noun) of \(FitnessFormat.spokenDuration(seconds: TimeInterval(seconds)))"
        }
        return noun
    }

    /// Convenience for one template: builds the index from `finishedWorkouts` first. Screens with many cards build the
    /// index once and use `make(for:index:)`.
    public static func make(
        for template: Template,
        finishedWorkouts: [Workout],
        maxLines: Int = 4,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TemplateCardSummary {
        make(
            for: template,
            index: LastPerformedIndex(finishedWorkouts: finishedWorkouts),
            maxLines: maxLines,
            now: now,
            calendar: calendar
        )
    }

    /// Same day or future `Today`; `Yesterday`; 2-13 days `N days ago`; 14-59 days `N weeks ago`; else `Jul 4, 2026`.
    public static func relativeText(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days =
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: date),
                to: calendar.startOfDay(for: now)
            ).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2..<14: return "\(days) days ago"
        case 14..<60: return "\(days / 7) weeks ago"
        default:
            return CalendarFormatting.monthDayYear(date, calendar: calendar)
        }
    }
}

extension String {
    /// `Today` becomes `today`, `5 days ago` stays; a date such as `Jul 4, 2026` keeps its capital month.
    fileprivate var lowercasedWord: String {
        self == "Today" || self == "Yesterday" ? lowercased() : self
    }
}
