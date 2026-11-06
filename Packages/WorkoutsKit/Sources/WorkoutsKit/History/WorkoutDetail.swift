import Foundation
import SwiftData

/// A finished workout as the History detail shows it (`docs/port/screens/history.md` section 2, "Detail"): a header, then
/// per exercise its completed sets, the records it set and a one-sentence accessibility label. Derived on read; nothing
/// here is stored.
public nonisolated struct WorkoutDetail: Hashable, Sendable {
    /// One completed set of an exercise.
    public struct SetLine: Identifiable, Hashable, Sendable {
        public var id: UUID
        /// `1`, `2`, or `W` / `D` / `F` in place of the number.
        public var label: String
        public var kind: SetKind
        /// `100 lb × 5`, `12 reps`, `45 s`, in the display unit.
        public var text: String
        /// True when this set holds a record the workout newly set.
        public var isPR: Bool
        /// `Set 2, 100 lb × 5`, `Set 1, warm-up, 60 lb × 8`, `..., personal record`.
        public var accessibilityLabel: String
    }

    /// One exercise of the workout that has at least one completed set.
    public struct ExerciseBlock: Identifiable, Hashable, Sendable {
        /// The `WorkoutExercise` row id.
        public var id: UUID
        public var exerciseID: UUID
        public var name: String
        public var note: String
        /// Display number of the superset it belongs to (1, 2, ... by first appearance); nil when it is alone.
        public var supersetNumber: Int?
        /// The best set as text (`100 lb × 5`); empty when no completed set carries a value.
        public var bestSetText: String
        public var sets: [SetLine]
        /// One line per record: `Est. 1RM: 117.5 lb`, `Reps: 8 at 100 lb`.
        public var prLines: [String]
        /// The whole block as one sentence for VoiceOver.
        public var accessibilityLabel: String
    }

    public var id: UUID
    public var name: String
    public var note: String
    public var startedAt: Date
    /// `Sunday, Nov 1 · 10:05 AM`.
    public var dateText: String
    public var durationText: String
    public var volumeText: String
    public var unit: WeightUnit
    /// Records the workout newly set, summed over its exercises (the same number as its History row).
    public var prCount: Int
    public var exercises: [ExerciseBlock]
    /// The header as one sentence for VoiceOver.
    public var headerAccessibilityLabel: String
}

nonisolated extension WorkoutDetail {
    // MARK: Health

    /// The header sentence with the matched Apple Health values appended (`..., 266 active calories, average heart rate
    /// 128, effort 6 Moderate, estimated`); only the values that exist. With no summary it is `headerAccessibilityLabel`
    /// unchanged. The summary is read from the model at display time (Health data lands after the workout was saved).
    @MainActor
    public func accessibilityLabel(health: HealthWorkoutSummary?, locale: Locale = .current) -> String {
        guard let health else { return headerAccessibilityLabel }
        var parts: [String] = []
        if let calories = health.activeEnergyKcal {
            parts.append("\(FitnessFormat.wholeNumber(calories)) active calories")
        }
        if let calories = health.totalEnergyKcal {
            parts.append("\(FitnessFormat.wholeNumber(calories)) total calories")
        }
        if let average = health.avgHeartRate {
            parts.append("average heart rate \(FitnessFormat.wholeNumber(average))")
        }
        if let maximum = health.maxHeartRate {
            parts.append("maximum heart rate \(FitnessFormat.wholeNumber(maximum))")
        }
        if let effort = health.effort {
            parts.append(
                "effort \(FitnessFormat.wholeScore(effort.score)) \(effort.word)"
                    + (effort.isEstimated ? ", estimated" : "")
            )
        }
        if let weather = FitnessFormat.weatherText(
            celsius: health.weatherTemperatureCelsius,
            humidityPercent: health.weatherHumidityPercent,
            locale: locale
        ) {
            parts.append("weather \(weather)")
        }
        return ([headerAccessibilityLabel] + parts).joined(separator: ", ")
    }

    // MARK: Building

    /// The detail of the finished workout `id`, or nil when it is not among `workouts` (or still running). Records are
    /// judged like the History rows: against sessions of the same exercise strictly before this workout, across every
    /// finished workout in `workouts`. An exercise with no completed set is left out.
    public static func make(
        id: UUID,
        from workouts: [Workout],
        weightType: (UUID) -> WeightType?,
        options: RecordsOptions,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WorkoutDetail? {
        let finished = workouts.filter(\.isFinished)
        guard let workout = finished.first(where: { $0.id == id }) else { return nil }

        // Only sessions of this workout's own exercises can matter for its records; the rest of the history is skipped.
        let sessionsByExercise = ExerciseBestSets.sessions(
            from: finished,
            weightType: weightType,
            exerciseIDs: Set((workout.exercises ?? []).map(\.exerciseID))
        )
        let rows = (workout.exercises ?? []).sorted { $0.position < $1.position }
        let numbers = SetTableLayout.supersetNumbers(for: rows.map(\.supersetGroup))

        var blocks: [ExerciseBlock] = []
        var prCount = 0
        var volumeTotal = 0.0
        for (row, number) in zip(rows, numbers) {
            // Each row's session comes from that row itself: an exercise can appear twice, and the to-many
            // relationship order is not guaranteed, so a shared per-exercise queue could pair another row's sets.
            let session = ExerciseBestSets.session(
                row: row,
                workout: workout,
                weightType: weightType(row.exerciseID) ?? .weighted
            )
            guard !session.sets.isEmpty else { continue }

            let type = session.weightType
            let prs = prsInSession(
                history: sessionsByExercise[row.exerciseID] ?? [],
                session: session,
                weightType: type,
                options: options
            )
            prCount += prs.count
            volumeTotal += volume(of: session.sets, weightType: type, displayUnit: options.displayUnit)
            blocks.append(block(row: row, session: session, prs: prs, number: number, options: options))
        }

        let seconds = HistoryList.duration(from: workout.startedAt, to: workout.finishedAt)
        let duration = HistoryList.durationText(seconds: seconds)
        let volumeText = HistoryList.volumeText(round05(volumeTotal), unit: options.displayUnit)
        let date = dateText(workout.startedAt, calendar: calendar, now: now)
        var parts = [workout.name, date, duration, volumeText]
        if prCount > 0 { parts.append(HistoryList.prText(count: prCount)) }
        if !workout.note.isEmpty { parts.append("Note: \(workout.note)") }
        return WorkoutDetail(
            id: workout.id,
            name: workout.name,
            note: workout.note,
            startedAt: workout.startedAt,
            dateText: date,
            durationText: duration,
            volumeText: volumeText,
            unit: options.displayUnit,
            prCount: prCount,
            exercises: blocks,
            headerAccessibilityLabel: parts.joined(separator: ", ")
        )
    }

    /// `Sunday, Nov 1 · 10:05 AM`; the year (`Sunday, Nov 1, 2025 · ...`) only when it is not the year of `now`.
    public static func dateText(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> String {
        let day = HistoryList.dateText(date, now: now, calendar: calendar)
        return "\(day) · \(CalendarFormatting.timeOfDay(date, calendar: calendar))"
    }

    private static func block(
        row: WorkoutExercise,
        session: Session,
        prs: [PersonalRecord],
        number: Int?,
        options: RecordsOptions
    ) -> ExerciseBlock {
        let unit = options.displayUnit
        let setIDs = (row.sets ?? []).filter(\.completed).sorted { $0.position < $1.position }.map(\.id)
        let best = bestSet(in: session.sets, weightType: session.weightType, options: options)
        let bestText =
            best.map {
                formatSetDetail(
                    weight: $0.weightInDisplayUnit,
                    unit: unit,
                    reps: $0.set.reps,
                    durationSeconds: $0.set.durationSeconds
                )
            } ?? ""

        // A set that holds a record gets the trophy; two identical sets never both do.
        var unclaimed = prs
        var lines: [SetLine] = []
        for (index, (id, set)) in zip(setIDs, session.sets).enumerated() {
            let shown = displayWeight(set, unit: unit)
            let text = formatSetDetail(
                weight: shown,
                unit: unit,
                reps: set.reps,
                durationSeconds: set.durationSeconds
            )
            let held = set.kind != .warmup && unclaimed.contains { holds($0, set: set, shownWeight: shown) }
            if held { unclaimed.removeAll { holds($0, set: set, shownWeight: shown) } }
            var sentence = SetInputFormat.setAccessibilityLabel(number: index + 1, kind: set.kind)
            if !text.isEmpty { sentence += ", \(text)" }
            if held { sentence += ", personal record" }
            lines.append(
                SetLine(
                    id: id,
                    label: SetInputFormat.setLabel(number: index + 1, kind: set.kind),
                    kind: set.kind,
                    text: text,
                    isPR: held,
                    accessibilityLabel: sentence
                )
            )
        }

        let prLines = prs.map { prLine($0, unit: unit, weightType: session.weightType) }
        var parts = [row.exerciseName]
        if let number { parts.append("superset \(number)") }
        if !row.note.isEmpty { parts.append("note: \(row.note)") }
        parts.append(contentsOf: lines.map(\.accessibilityLabel))
        parts.append(contentsOf: prLines.map { "record, \($0)" })
        return ExerciseBlock(
            id: row.id,
            exerciseID: row.exerciseID,
            name: row.exerciseName,
            note: row.note,
            supersetNumber: number,
            bestSetText: bestText,
            sets: lines,
            prLines: prLines,
            accessibilityLabel: parts.joined(separator: ". ")
        )
    }

    /// A set's weight in the display unit: exact when logged in it, otherwise converted and rounded to 0.5.
    private static func displayWeight(_ set: LoggedSet, unit: WeightUnit) -> Double? {
        guard let weight = set.weight else { return nil }
        if set.unit == unit { return weight }
        return round05(convert(weight, from: set.unit, to: unit))
    }

    /// Whether `set` is the one that set `record`.
    private static func holds(_ record: PersonalRecord, set: LoggedSet, shownWeight: Double?) -> Bool {
        switch record.kind {
        case .longestDuration:
            return (set.durationSeconds ?? 0) == Int(record.value.rounded())
        case .e1rm, .heaviest, .bestVolumeSet, .repsAtWeight:
            return (set.reps ?? 0) == record.reps && abs((shownWeight ?? 0) - record.weight) < 0.0001
        }
    }

    /// `Est. 1RM: 117.5 lb`, `Heaviest: 100 lb` (`Least assistance: 20 lb`), `Set volume: 500 lb`, `Reps: 8 at 100 lb`,
    /// `Duration: 1:30`.
    public static func prLine(_ record: PersonalRecord, unit: WeightUnit, weightType: WeightType) -> String {
        switch record.kind {
        case .e1rm:
            return "Est. 1RM: \(WeightFormat.groupedText(record.value, unit: unit))"
        case .heaviest:
            let label = weightType.category == .assisted ? "Least assistance" : "Heaviest"
            return "\(label): \(WeightFormat.groupedText(record.value, unit: unit))"
        case .bestVolumeSet:
            return "Set volume: \(WeightFormat.groupedText(record.value, unit: unit))"
        case .repsAtWeight:
            let load = record.weight > 0 ? " at \(WeightFormat.groupedText(record.weight, unit: unit))" : ""
            return "Reps: \(record.reps)\(load)"
        case .longestDuration:
            return "Duration: \(ClockFormat.compact(seconds: Int(record.value.rounded())))"
        }
    }
}

// MARK: - Save as Template

/// Where a saved template goes.
public enum TemplateDestination {
    /// No folder.
    case none
    case folder(TemplateFolder)
    /// A folder made on the spot with this name.
    case newFolder(named: String)
}

extension WorkoutDetail {
    /// Inserts a template that copies `workout`'s completed sets as planned values: exercises in order (those with no
    /// completed set are left out), set kinds, weights, reps, durations, distances, units, bars, rest, supersets and
    /// notes, all under new ids. Saves the context; on a failed save the insertions are rolled back and the error is
    /// thrown.
    @MainActor
    @discardableResult
    public static func saveAsTemplate(
        _ workout: Workout,
        named name: String? = nil,
        to destination: TemplateDestination,
        in context: ModelContext,
        now: Date = .now
    ) throws -> Template {
        let folder: TemplateFolder?
        switch destination {
        case .none:
            folder = nil
        case .folder(let existing):
            folder = existing
        case .newFolder(let folderName):
            let all = try context.fetch(FetchDescriptor<TemplateFolder>())
            let made = TemplateFolder(
                name: folderName,
                position: (all.map(\.position).max() ?? -1) + 1,
                createdAt: now,
                updatedAt: now
            )
            context.insert(made)
            folder = made
        }

        var trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { trimmed = workout.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        let siblings = try context.fetch(FetchDescriptor<Template>()).filter { $0.folder?.id == folder?.id }
        let template = Template(
            name: trimmed.isEmpty ? "Workout" : trimmed,
            note: workout.note,
            position: (siblings.map(\.position).max() ?? -1) + 1,
            folder: folder,
            createdAt: now,
            updatedAt: now
        )
        context.insert(template)

        var position = 0
        for row in (workout.exercises ?? []).sorted(by: { $0.position < $1.position }) {
            let sets = (row.sets ?? []).filter(\.completed).sorted { $0.position < $1.position }
            guard !sets.isEmpty else { continue }
            let planned = TemplateExercise(
                exerciseID: row.exerciseID,
                exerciseName: row.exerciseName,
                position: position,
                supersetGroup: row.supersetGroup,
                note: row.note,
                restSeconds: row.restSeconds,
                unit: row.unit,
                barType: row.barType,
                barWeight: row.barWeight,
                template: template,
                updatedAt: now
            )
            context.insert(planned)
            for (index, set) in sets.enumerated() {
                context.insert(
                    TemplateSet(
                        position: index,
                        kind: set.kind,
                        weight: set.weight,
                        reps: set.reps,
                        durationSeconds: set.durationSeconds,
                        distanceMeters: set.distanceMeters,
                        templateExercise: planned
                    )
                )
            }
            position += 1
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return template
    }
}
