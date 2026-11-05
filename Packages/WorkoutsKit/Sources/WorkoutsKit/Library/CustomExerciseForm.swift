import Foundation
import SwiftData

/// The custom exercise form's rules (task 4.4): validation of a draft, whether history references an exercise, and
/// create / update / archive / delete on the `Exercise` model that keep the `ExerciseStore` in step.
public nonisolated enum CustomExerciseForm {
    /// The name's maximum length, after trimming.
    public static let maxNameLength = 120
    /// The longest rest timer, in seconds.
    public static let maxRestSeconds = 3600
    /// The largest custom bar weight, in the exercise's unit.
    public static let maxBarWeight = 1000.0

    /// What the form edits. Rest and bar weight are text so that a half-typed value can be reported, not lost.
    public struct Draft: Sendable, Hashable {
        public var name: String
        /// A library body-part key; empty = none chosen.
        public var bodyPart: String
        /// Library equipment keys.
        public var equipment: [String]
        public var weightType: WeightType
        /// One step per line.
        public var instructions: String
        /// nil = the Settings default unit.
        public var unit: WeightUnit?
        /// The bar the first warm-up step starts from. Follows the weight type until the user picks one: see
        /// ``defaultBarType(for:)`` and ``setWeightType(_:)``.
        public var barType: BarType
        public var barWeightText: String
        /// Blank = the default rest timer.
        public var restText: String

        public init(
            name: String = "",
            bodyPart: String = "",
            equipment: [String] = [],
            weightType: WeightType = .weighted,
            instructions: String = "",
            unit: WeightUnit? = nil,
            barType: BarType? = nil,
            barWeightText: String = "",
            restText: String = ""
        ) {
            self.name = name
            self.bodyPart = bodyPart
            self.equipment = equipment
            self.weightType = weightType
            self.instructions = instructions
            self.unit = unit
            self.barType = barType ?? Self.defaultBarType(for: weightType)
            self.barWeightText = barWeightText
            self.restText = restText
        }

        /// The draft that edits `exercise`.
        public init(_ exercise: Exercise) {
            self.init(
                name: exercise.name,
                bodyPart: exercise.bodyPart,
                equipment: exercise.equipment,
                weightType: exercise.weightType,
                instructions: exercise.instructions.joined(separator: "\n"),
                unit: exercise.unit,
                barType: exercise.barType,
                barWeightText: exercise.barWeight.map { Self.format($0) } ?? "",
                restText: exercise.restSeconds.map(String.init) ?? ""
            )
        }

        /// The bar a new exercise of this weight type starts with: an Olympic bar for a barbell, none otherwise.
        public static func defaultBarType(for weightType: WeightType) -> BarType {
            weightType == .barbell ? .olympic : BarType.none
        }

        /// Changes the weight type. A bar that is still the old type's default follows to the new type's default; a bar
        /// the user picked (anything else) is kept.
        public mutating func setWeightType(_ newValue: WeightType) {
            if barType == Self.defaultBarType(for: weightType) { barType = Self.defaultBarType(for: newValue) }
            weightType = newValue
        }

        /// The name without surrounding whitespace.
        public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

        /// The parsed rest timer: nil when blank or invalid.
        public var restSeconds: Int? { CustomExerciseForm.parseRest(restText) }

        /// The parsed custom bar weight: nil when blank or invalid.
        public var barWeight: Double? { CustomExerciseForm.parseBarWeight(barWeightText) }

        /// Non-empty, trimmed lines of the notes.
        public var instructionSteps: [String] {
            instructions.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        static func format(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(value)
        }
    }

    /// Something wrong with a draft; `message` is what the form shows.
    public enum Issue: Sendable, Hashable {
        case nameMissing
        case nameTooLong
        case nameTaken
        case restInvalid
        case barWeightInvalid

        public var message: String {
            switch self {
            case .nameMissing: "Give the exercise a name."
            case .nameTooLong: "The name can be at most \(CustomExerciseForm.maxNameLength) characters."
            case .nameTaken: "An exercise with this name already exists."
            case .restInvalid: "Rest timer is a whole number of seconds, 0 to \(CustomExerciseForm.maxRestSeconds)."
            case .barWeightInvalid: "Bar weight is a number from 0 to 1000."
            }
        }
    }

    // MARK: Parsing

    /// A whole number of seconds, 0 to 3600. Blank, fractional, negative, or too large is nil.
    public static func parseRest(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isASCII), trimmed.allSatisfy(\.isNumber),
            let value = Int(trimmed), value <= maxRestSeconds
        else { return nil }
        return value
    }

    /// A number 0 to 1000; a comma decimal is accepted. Blank or invalid is nil.
    public static func parseBarWeight(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite, value >= 0, value <= maxBarWeight else {
            return nil
        }
        return value
    }

    // MARK: Validation

    /// Every problem with `draft`, in field order; empty means it can be saved. The name must be unique, ignoring case,
    /// accents and surrounding space, among every library and custom exercise (retired included) except `id`, the
    /// exercise being edited.
    @MainActor public static func validate(_ draft: Draft, editing id: UUID? = nil, in store: ExerciseStore) -> [Issue]
    {
        var issues: [Issue] = []
        let name = draft.trimmedName
        if name.isEmpty {
            issues.append(.nameMissing)
        } else if name.count > maxNameLength {
            issues.append(.nameTooLong)
        } else if isNameTaken(name, excluding: id, in: store) {
            issues.append(.nameTaken)
        }
        let rest = draft.restText.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty, parseRest(rest) == nil { issues.append(.restInvalid) }
        if draft.barType == .custom, draft.barWeight == nil { issues.append(.barWeightInvalid) }
        return issues
    }

    /// Whether another exercise already shows this name.
    @MainActor public static func isNameTaken(_ name: String, excluding id: UUID? = nil, in store: ExerciseStore)
        -> Bool
    {
        let folded = ExerciseStore.fold(name.trimmingCharacters(in: .whitespacesAndNewlines))
        return store.all(includeRetired: true).contains { $0.id != id && ExerciseStore.fold($0.name) == folded }
    }

    // MARK: References

    /// Whether any template or workout row uses the exercise, which decides Archive over Delete.
    public static func isReferenced(exerciseID: UUID, in context: ModelContext) -> Bool {
        let inTemplates = FetchDescriptor<TemplateExercise>(predicate: #Predicate { $0.exerciseID == exerciseID })
        let inWorkouts = FetchDescriptor<WorkoutExercise>(predicate: #Predicate { $0.exerciseID == exerciseID })
        let templates = (try? context.fetchCount(inTemplates)) ?? 0
        let workouts = (try? context.fetchCount(inWorkouts)) ?? 0
        return templates > 0 || workouts > 0
    }

    // MARK: Changes

    /// Inserts a new custom exercise from `draft` and refreshes `store`. The draft should have no issues.
    @discardableResult
    @MainActor public static func create(_ draft: Draft, in context: ModelContext, store: ExerciseStore) throws
        -> Exercise
    {
        let exercise = Exercise()
        apply(draft, to: exercise)
        context.insert(exercise)
        try commit(context, store: store)
        return exercise
    }

    /// Writes `draft` onto `exercise` and refreshes `store`.
    @MainActor public static func update(
        _ exercise: Exercise,
        from draft: Draft,
        in context: ModelContext,
        store: ExerciseStore
    ) throws {
        apply(draft, to: exercise)
        try commit(context, store: store)
    }

    /// Retires `exercise`: hidden unless Show Retired, still in history and fetchable by id.
    @MainActor public static func archive(_ exercise: Exercise, in context: ModelContext, store: ExerciseStore) throws {
        exercise.retired = true
        exercise.updatedAt = Date()
        try commit(context, store: store)
    }

    /// Deletes `exercise` (and its sticky note) when nothing references it; returns whether it did.
    @discardableResult
    @MainActor public static func delete(_ exercise: Exercise, in context: ModelContext, store: ExerciseStore) throws
        -> Bool
    {
        try delete(exercise, in: context, store: store, saveHook: nil)
    }

    /// ``delete(_:in:store:)`` with a test seam: `saveHook` runs just before the save, so a test can fail it.
    @discardableResult
    @MainActor static func delete(
        _ exercise: Exercise,
        in context: ModelContext,
        store: ExerciseStore,
        saveHook: (() throws -> Void)?
    ) throws -> Bool {
        let id = exercise.id
        guard !isReferenced(exerciseID: id, in: context) else { return false }
        let notes = try context.fetch(FetchDescriptor<StickyNote>(predicate: #Predicate { $0.exerciseID == id }))
        for note in notes { context.delete(note) }
        context.delete(exercise)
        try commit(context, store: store, saveHook: saveHook)
        return true
    }

    /// The custom exercise with this id, if any.
    public static func exercise(id: UUID, in context: ModelContext) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func apply(_ draft: Draft, to exercise: Exercise) {
        exercise.name = draft.trimmedName
        exercise.bodyPart = draft.bodyPart
        exercise.equipment = draft.equipment
        exercise.weightType = draft.weightType
        exercise.instructions = draft.instructionSteps
        exercise.unit = draft.unit
        exercise.barType = draft.barType
        exercise.barWeight = draft.barType == .custom ? draft.barWeight : nil
        exercise.restSeconds = draft.restSeconds
        exercise.updatedAt = Date()
    }

    /// Saves and refreshes `store`. A failed save rolls the context back, so a half-applied edit or delete is not
    /// committed by the next unrelated save.
    @MainActor private static func commit(
        _ context: ModelContext,
        store: ExerciseStore,
        saveHook: (() throws -> Void)? = nil
    ) throws {
        do {
            try saveHook?()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        store.setCustom(try context.fetch(FetchDescriptor<Exercise>()))
    }
}
