import Testing

@testable import WorkoutsKit

struct UnitsTests {
    @Test func hundredPoundsTiesItsKgEquivalent() {
        #expect(weightsEqual(100, .lb, 45.359237, .kg))
    }

    @Test func seventeenAndAHalfPoundsIsLighterThanEightKg() {
        #expect(!weightsEqual(17.5, .lb, 8, .kg))
        #expect(toKg(17.5, unit: .lb) < 8)
    }

    @Test func sameUnitConversionIsUntouched() {
        #expect(convert(17.25, from: .lb, to: .lb) == 17.25)
        #expect(convert(0.1 + 0.2, from: .kg, to: .kg) == 0.1 + 0.2)
    }

    @Test func conversionUsesExactFactor() {
        #expect(toKg(1, unit: .lb) == kgPerLb)
        #expect(abs(convert(45.359237, from: .kg, to: .lb) - 100) < 1e-9)
        #expect(toKg(5, unit: .kg) == 5)
    }

    @Test func round05RoundsToNearestHalf() {
        #expect(round05(70.2) == 70)
        #expect(round05(70.3) == 70.5)
        #expect(round05(70.74) == 70.5)
        #expect(round05(70.75) == 71)
        #expect(round05(0) == 0)
    }

    @Test func enumRawValuesMatchSpec() {
        #expect(SetKind.allCases.map(\.rawValue) == ["warmup", "normal", "drop", "failure"])
        #expect(WeightUnit.allCases.map(\.rawValue) == ["lb", "kg"])
        #expect(E1RMFormula.allCases.map(\.rawValue) == ["epley", "brzycki"])
        #expect(BarType.allCases.map(\.rawValue) == ["olympic", "ez", "none", "custom"])
        #expect(
            WeightType.allCases.map(\.rawValue)
                == ["barbell", "bodyweight", "dumbbell", "machine", "unweighted", "weighted", "assisted", "band"]
        )
    }

    @Test func weightTypeCategories() {
        for type in [WeightType.barbell, .dumbbell, .machine, .weighted] { #expect(type.category == .strength) }
        for type in [WeightType.bodyweight, .unweighted, .band] { #expect(type.category == .repBased) }
        #expect(WeightType.assisted.category == .assisted)
        #expect(WeightType.category(forRawValue: "kettlebell") == .strength)
        #expect(WeightType.category(forRawValue: "band") == .repBased)
    }

    @Test func countedSetIsCompletedAndNotWarmup() {
        #expect(LoggedSet(kind: .normal, completed: true).counts)
        #expect(LoggedSet(kind: .drop, completed: true).counts)
        #expect(LoggedSet(kind: .failure, completed: true).counts)
        #expect(!LoggedSet(kind: .warmup, completed: true).counts)
        #expect(!LoggedSet(kind: .normal, completed: false).counts)
    }

    @Test func optionsZeroValueIsEpleyInKg() {
        let options = RecordsOptions()
        #expect(options.formula == .epley)
        #expect(options.displayUnit == .kg)
    }
}
