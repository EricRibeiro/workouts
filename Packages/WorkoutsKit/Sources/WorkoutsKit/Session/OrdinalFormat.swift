import Foundation

/// The ordinal in "Your 615th workout".
public nonisolated enum OrdinalFormat {
    /// `1st`, `2nd`, `3rd`, `615th` (en_US).
    public static func string(_ number: Int) -> String {
        let format = NumberFormatter()
        format.locale = Locale(identifier: "en_US")
        format.numberStyle = .ordinal
        return format.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}
