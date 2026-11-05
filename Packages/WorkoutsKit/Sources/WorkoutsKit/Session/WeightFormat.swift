import Foundation

/// The one place a weight becomes text. Built on `FloatingPointFormatStyle` (en_US, so the digits never follow the
/// device locale): at most two decimals, no trailing zeros, and `-0` reads `0`.
public nonisolated enum WeightFormat {
    /// `27.5`, `100`, `22.25`; no grouping separators, so it is safe to put in an editable field.
    public static func number(_ weight: Double) -> String {
        clean(weight.formatted(plainStyle))
    }

    /// `number(_:)` with thousands separators: `1,929`, `117.5`.
    public static func groupedNumber(_ weight: Double) -> String {
        clean(weight.formatted(groupedStyle))
    }

    /// `27.5 lb`, `100 kg`.
    public static func text(_ weight: Double, unit: WeightUnit) -> String {
        "\(number(weight)) \(unit.rawValue)"
    }

    /// `1,929 lb`, `117.5 kg`.
    public static func groupedText(_ weight: Double, unit: WeightUnit) -> String {
        "\(groupedNumber(weight)) \(unit.rawValue)"
    }

    private static func clean(_ text: String) -> String { text == "-0" ? "0" : text }

    private static let plainStyle = FloatingPointFormatStyle<Double>.number
        .locale(Locale(identifier: "en_US"))
        .grouping(.never)
        .rounded(rule: .toNearestOrAwayFromZero)
        .precision(.fractionLength(0...2))

    /// Halves to even, like `NumberFormatter`'s default.
    private static let groupedStyle = FloatingPointFormatStyle<Double>.number
        .locale(Locale(identifier: "en_US"))
        .grouping(.automatic)
        .precision(.fractionLength(0...2))
}
