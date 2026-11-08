import Foundation

/// Pure logic behind the keyboard toolbar of the set table (task 2.2b): the −/+ step sizes, stepping a field's text, and the
/// Next order weight → reps → the next row. Steps come from the web app's `numpadKeys.ts` (`stepFor`, `applyKey`).
public nonisolated enum SetKeyboard {
    /// Which input of a set row a keyboard step or focus move refers to.
    public enum Column: Hashable, Sendable {
        case weight
        /// Reps, or the duration field of a time exercise.
        case reps
    }

    /// One focusable cell of a set row.
    public struct Field: Hashable, Sendable {
        public var setID: UUID
        public var column: Column

        public init(setID: UUID, column: Column) {
            self.setID = setID
            self.column = column
        }
    }

    /// Direction of the −step / +step keys.
    public enum Direction: Sendable {
        case decrement
        case increment

        var sign: Double { self == .increment ? 1 : -1 }
    }

    /// The jump of the −/+ keys: 2.5 lb or 1.25 kg for weight, doubled for a barbell (plates go on in pairs); 1 for reps and
    /// 5 seconds for time.
    public static func step(
        column: Column,
        unit: WeightUnit,
        weightType: WeightType,
        measure: SetInputFormat.Measure = .reps
    ) -> Double {
        guard column == .weight else { return measure == .duration ? 5 : 1 }
        let base = unit == .lb ? 2.5 : 1.25
        return weightType == .barbell ? base * 2 : base
    }

    /// The step as spoken for VoiceOver: "2.5 pounds", "1.25 kilograms", "1 rep", "5 seconds".
    public static func stepDescription(
        column: Column,
        unit: WeightUnit,
        weightType: WeightType,
        measure: SetInputFormat.Measure = .reps
    ) -> String {
        let size = step(column: column, unit: unit, weightType: weightType, measure: measure)
        switch column {
        case .weight:
            return "\(SetInputFormat.weightText(size)) \(unit == .kg ? "kilograms" : "pounds")"
        case .reps:
            return measure == .duration ? "5 seconds" : "1 rep"
        }
    }

    /// The field text after a −/+ press: the current value moved by one step, never below 0, weights at most 2 decimals,
    /// reps whole numbers and time `m:ss` (web `applyKey`). An empty cell steps from its greyed `placeholder` (the Previous / plan
    /// value checking the set would fill in; JC114), so a cell showing 60 goes to 62.5 on +. Without a usable placeholder
    /// (the default, or "–"), and for unparsable text, the base is 0.
    public static func stepped(
        _ text: String,
        column: Column,
        direction: Direction,
        unit: WeightUnit,
        weightType: WeightType,
        placeholder: String = "",
        measure: SetInputFormat.Measure = .reps
    ) -> String {
        let size = step(column: column, unit: unit, weightType: weightType, measure: measure)
        let text = text.trimmingCharacters(in: .whitespaces).isEmpty ? placeholder : text
        switch column {
        case .weight:
            let current = SetInputFormat.parseWeight(text) ?? 0
            return SetInputFormat.weightText(max(0, current + direction.sign * size))
        case .reps where measure == .duration:
            let current = SetInputFormat.parseDurationText(text) ?? 0
            return SetInputFormat.durationText(max(0, current + Int(direction.sign * size)))
        case .reps:
            let current = SetInputFormat.parseCount(text) ?? 0
            return SetInputFormat.countText(max(0, current + Int(direction.sign * size)))
        }
    }

    /// Where Next goes: weight → reps → the next row's weight. Rows in `weightlessSetIDs` have no weight column, so they
    /// are entered at reps. nil after the last row's reps (or when `field` is not in `orderedSetIDs`): dismiss the keyboard.
    public static func nextField(
        after field: Field,
        in orderedSetIDs: [UUID],
        weightlessSetIDs: Set<UUID> = []
    ) -> Field? {
        guard let index = orderedSetIDs.firstIndex(of: field.setID) else { return nil }
        if field.column == .weight, !weightlessSetIDs.contains(field.setID) {
            return Field(setID: field.setID, column: .reps)
        }
        guard index + 1 < orderedSetIDs.count else { return nil }
        let nextID = orderedSetIDs[index + 1]
        return Field(setID: nextID, column: weightlessSetIDs.contains(nextID) ? .reps : .weight)
    }
}
