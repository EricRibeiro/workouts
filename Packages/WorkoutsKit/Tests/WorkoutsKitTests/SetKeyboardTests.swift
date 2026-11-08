import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct SetKeyboardTests {
    @Test(arguments: [
        (WeightUnit.lb, WeightType.weighted, 2.5), (.kg, .weighted, 1.25), (.lb, .bodyweight, 2.5),
        (.lb, .barbell, 5), (.kg, .barbell, 2.5), (.kg, .dumbbell, 1.25),
    ])
    func weightStep(unit: WeightUnit, type: WeightType, expected: Double) {
        #expect(SetKeyboard.step(column: .weight, unit: unit, weightType: type) == expected)
    }

    @Test(arguments: WeightType.allCases)
    func repsAndTimeStepIsOne(type: WeightType) {
        #expect(SetKeyboard.step(column: .reps, unit: .lb, weightType: type) == 1)
        #expect(SetKeyboard.step(column: .reps, unit: .kg, weightType: type) == 1)
    }

    @Test func stepDescriptionIsSpoken() {
        #expect(SetKeyboard.stepDescription(column: .weight, unit: .lb, weightType: .weighted) == "2.5 pounds")
        #expect(SetKeyboard.stepDescription(column: .weight, unit: .lb, weightType: .barbell) == "5 pounds")
        #expect(SetKeyboard.stepDescription(column: .weight, unit: .kg, weightType: .weighted) == "1.25 kilograms")
        #expect(SetKeyboard.stepDescription(column: .reps, unit: .kg, weightType: .barbell) == "1 rep")
        #expect(
            SetKeyboard.stepDescription(column: .reps, unit: .kg, weightType: .barbell, measure: .duration)
                == "1 second"
        )
    }

    @Test func steppingWeight() {
        func go(
            _ text: String,
            _ direction: SetKeyboard.Direction,
            _ unit: WeightUnit = .kg,
            _ type: WeightType = .weighted
        )
            -> String
        {
            SetKeyboard.stepped(text, column: .weight, direction: direction, unit: unit, weightType: type)
        }
        #expect(go("60", .increment) == "61.25")
        #expect(go("61.25", .decrement) == "60")
        #expect(go("", .increment) == "1.25")
        #expect(go("abc", .increment, .lb) == "2.5")
        #expect(go("100", .increment, .lb, .barbell) == "105")
        #expect(go("27,5", .increment, .lb) == "30")
        // Clamped at zero, never negative.
        #expect(go("1", .decrement) == "0")
        #expect(go("", .decrement) == "0")
        // Two decimals at most.
        #expect(go("0.333", .increment) == "1.58")
    }

    @Test func emptyCellStepsFromItsPlaceholder() {
        func weight(_ text: String, _ placeholder: String, _ direction: SetKeyboard.Direction) -> String {
            SetKeyboard.stepped(
                text,
                column: .weight,
                direction: direction,
                unit: .kg,
                weightType: .barbell,
                placeholder: placeholder
            )
        }
        func reps(_ text: String, _ placeholder: String, _ direction: SetKeyboard.Direction) -> String {
            SetKeyboard.stepped(
                text,
                column: .reps,
                direction: direction,
                unit: .kg,
                weightType: .barbell,
                placeholder: placeholder
            )
        }
        #expect(weight("", "60", .increment) == "62.5")
        #expect(weight("", "60", .decrement) == "57.5")
        #expect(reps("", "8", .increment) == "9")
        #expect(reps("", "8", .decrement) == "7")
        // A typed value wins over the placeholder; no usable placeholder steps from 0.
        #expect(weight("70", "60", .increment) == "72.5")
        #expect(weight("", "–", .increment) == "2.5")
        #expect(reps("", "–", .decrement) == "0")
        #expect(reps("", "", .increment) == "1")
    }

    @Test func steppingRepsAndTime() {
        func go(_ text: String, _ direction: SetKeyboard.Direction) -> String {
            SetKeyboard.stepped(text, column: .reps, direction: direction, unit: .kg, weightType: .barbell)
        }
        #expect(go("8", .increment) == "9")
        #expect(go("8", .decrement) == "7")
        #expect(go("", .increment) == "1")
        #expect(go("0", .decrement) == "0")
        #expect(go("", .decrement) == "0")
        #expect(go("44", .increment) == "45")
    }

    @Test func nextFieldOrder() {
        let ids = (0..<3).map { _ in UUID() }
        #expect(
            SetKeyboard.nextField(after: .init(setID: ids[0], column: .weight), in: ids)
                == .init(setID: ids[0], column: .reps)
        )
        #expect(
            SetKeyboard.nextField(after: .init(setID: ids[0], column: .reps), in: ids)
                == .init(setID: ids[1], column: .weight)
        )
        #expect(
            SetKeyboard.nextField(after: .init(setID: ids[1], column: .reps), in: ids)
                == .init(setID: ids[2], column: .weight)
        )
        // The last field dismisses.
        #expect(SetKeyboard.nextField(after: .init(setID: ids[2], column: .reps), in: ids) == nil)
        // Unknown row: dismiss.
        #expect(SetKeyboard.nextField(after: .init(setID: UUID(), column: .weight), in: ids) == nil)
        #expect(SetKeyboard.nextField(after: .init(setID: ids[0], column: .weight), in: []) == nil)
    }

    @Test func rowsWithoutWeightSkipIt() {
        let ids = (0..<3).map { _ in UUID() }
        let weightless: Set = [ids[1]]
        // Reps of row 0 goes to row 1's reps, not its weight.
        #expect(
            SetKeyboard.nextField(
                after: .init(setID: ids[0], column: .reps),
                in: ids,
                weightlessSetIDs: weightless
            ) == .init(setID: ids[1], column: .reps)
        )
        // From a weightless row's reps on to the next row's weight.
        #expect(
            SetKeyboard.nextField(
                after: .init(setID: ids[1], column: .reps),
                in: ids,
                weightlessSetIDs: weightless
            ) == .init(setID: ids[2], column: .weight)
        )
        // A weight field of a weightless row (stale focus) still moves on to reps.
        #expect(
            SetKeyboard.nextField(
                after: .init(setID: ids[1], column: .weight),
                in: ids,
                weightlessSetIDs: weightless
            ) == .init(setID: ids[2], column: .weight)
        )
        // Weightless last row ends.
        #expect(
            SetKeyboard.nextField(
                after: .init(setID: ids[2], column: .reps),
                in: ids,
                weightlessSetIDs: [ids[2]]
            ) == nil
        )
    }
}
