import Foundation

/// What a template card shows (`workout.md` sections 2 and 3): the exercise count, the first few `N × Name` lines with
/// their superset group, and when the template was last performed. Pure over the models; the views only lay it out.
public struct TemplateCardSummary: Sendable, Equatable {
    /// One exercise line, e.g. `3 × Bench Press`.
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

    /// Summarises `template`. `finishedWorkouts` is every finished workout; the last performance is the newest start
    /// among those done from the template, else among those with the same name (case-insensitive; imported history is
    /// not linked), in-progress ones never counting.
    public static func make(
        for template: Template,
        finishedWorkouts: [Workout],
        maxLines: Int = 4,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TemplateCardSummary {
        let exercises = (template.exercises ?? []).sorted {
            $0.position != $1.position ? $0.position < $1.position : $0.id.uuidString < $1.id.uuidString
        }
        let lines = exercises.prefix(max(0, maxLines)).map { exercise in
            Line(
                id: exercise.id,
                text: "\(exercise.sets?.count ?? 0) × \(exercise.exerciseName)",
                supersetGroup: exercise.supersetGroup
            )
        }
        let finished = finishedWorkouts.filter { $0.finishedAt != nil }
        let linked = finished.filter { $0.template?.id == template.id }
        let candidates =
            linked.isEmpty
            ? finished.filter { $0.name.compare(template.name, options: .caseInsensitive) == .orderedSame }
            : linked
        let last = candidates.map(\.startedAt).max()
        return TemplateCardSummary(
            exerciseCount: exercises.count,
            lines: Array(lines),
            overflow: max(0, exercises.count - lines.count),
            lastPerformed: last.map { relativeText($0, now: now, calendar: calendar) }
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
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US")
            format.calendar = calendar
            format.timeZone = calendar.timeZone
            format.dateFormat = "MMM d, yyyy"
            return format.string(from: date)
        }
    }
}

extension String {
    /// `Today` becomes `today`, `5 days ago` stays; a date such as `Jul 4, 2026` keeps its capital month.
    fileprivate var lowercasedWord: String {
        self == "Today" || self == "Yesterday" ? lowercased() : self
    }
}
