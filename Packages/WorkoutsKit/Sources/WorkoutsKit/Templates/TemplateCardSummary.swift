import Foundation

/// What a template card shows (`workout.md` sections 2 and 3): the exercise count, the first few exercise names with
/// their superset group, and when the template was last performed. Pure over the models; the views only lay it out.
public struct TemplateCardSummary: Sendable, Equatable {
    /// One exercise line: the exercise's name alone (the template preview shows the sets).
    public struct Line: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let text: String
        public let supersetGroup: Int?
    }

    public let exerciseCount: Int
    /// The first `maxLines` exercises in template order.
    public let lines: [Line]
    /// Exercises beyond `lines`.
    public let overflow: Int
    /// `Today`, `Yesterday`, `5 days ago`, `3 weeks ago` or a date; nil when the template was never performed.
    public let lastPerformed: String?

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

    /// The card's one VoiceOver sentence: `name, 7 exercises, last done 5 days ago` (the last part only when known).
    public func accessibilityLabel(name: String) -> String {
        var parts = [name, countText]
        if let lastPerformed { parts.append("last done \(lastPerformed.lowercasedWord)") }
        return parts.joined(separator: ", ")
    }

    /// When each template was last performed, built in one pass over the finished workouts so a screen full of cards
    /// costs one scan (and one relationship read per workout) instead of one per card. The rule: the newest start among
    /// finished workouts done from the template, else among those with the same name (case-insensitive; imported
    /// history is not linked). In-progress workouts never count.
    public nonisolated struct LastPerformedIndex: Sendable, Equatable {
        private var byTemplate: [UUID: Date] = [:]
        private var byName: [String: Date] = [:]

        public init() {}

        public init(finishedWorkouts: [Workout]) {
            for workout in finishedWorkouts where workout.isFinished {
                let started = workout.startedAt
                if let id = workout.template?.id, byTemplate[id].map({ started > $0 }) ?? true {
                    byTemplate[id] = started
                }
                let name = Self.key(workout.name)
                if byName[name].map({ started > $0 }) ?? true { byName[name] = started }
            }
        }

        /// The newest linked start, else the newest same-name start; nil when never performed.
        public func lastPerformed(of template: Template) -> Date? {
            byTemplate[template.id] ?? byName[Self.key(template.name)]
        }

        private static func key(_ name: String) -> String { name.lowercased() }
    }

    /// Summarises `template` with a prebuilt `index` (see `LastPerformedIndex`). A superset bar is kept on a line only
    /// when at least two members of its group are among the lines: a partner folded into "+ N more" leaves a lone bar
    /// that marks nothing.
    public static func make(
        for template: Template,
        index: LastPerformedIndex,
        maxLines: Int = 4,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TemplateCardSummary {
        let exercises = (template.exercises ?? []).sorted {
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
                supersetGroup: exercise.supersetGroup.flatMap { (groupSizes[$0] ?? 0) >= 2 ? $0 : nil }
            )
        }
        return TemplateCardSummary(
            exerciseCount: exercises.count,
            lines: lines,
            overflow: max(0, exercises.count - lines.count),
            lastPerformed: index.lastPerformed(of: template).map { relativeText($0, now: now, calendar: calendar) }
        )
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
