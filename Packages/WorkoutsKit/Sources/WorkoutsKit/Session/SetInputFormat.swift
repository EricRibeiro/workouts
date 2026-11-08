import Foundation

/// Pure parsing and formatting behind a set row's text fields and labels (task 2.2a). Everything the view shows or
/// commits goes through here so it is tested without a simulator.
public nonisolated enum SetInputFormat {
    /// What the second input column of a set row measures.
    public enum Measure: String, Sendable, Hashable, CaseIterable {
        case reps
        /// Time exercises: whole seconds, shown and typed as `m:ss`.
        case duration
    }

    /// The kind a tap on the set label moves to: normal → W → D → F → normal.
    public static func nextKind(after kind: SetKind) -> SetKind {
        switch kind {
        case .normal: .warmup
        case .warmup: .drop
        case .drop: .failure
        case .failure: .normal
        }
    }

    /// The set label: the 1-based `number` for a normal set, else the kind's letter (`W`, `D`, `F`).
    public static func setLabel(number: Int, kind: SetKind) -> String {
        switch kind {
        case .normal: "\(number)"
        case .warmup: "W"
        case .drop: "D"
        case .failure: "F"
        }
    }

    /// VoiceOver label of the set label: `Set 2`, `Set 2, warm-up`.
    public static func setAccessibilityLabel(number: Int, kind: SetKind) -> String {
        kind == .normal ? "Set \(number)" : "Set \(number), \(formatKind(kind))"
    }

    /// The largest weight a field accepts (in the row's unit); anything above is rejected as a typo.
    public static let maxWeight = 10_000.0

    /// Plain decimal text only: an optional sign, digits, at most one `.` (commas are already mapped to it). Rejects
    /// exponents (`1e307`), hex (`0x10`), `inf` and `nan`, which `Double(_:)` would otherwise accept.
    private static func plainDecimal(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        let body = cleaned.hasPrefix("-") || cleaned.hasPrefix("+") ? cleaned.dropFirst() : cleaned[...]
        guard body.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
            body.contains(where: \.isNumber), body.filter({ $0 == "." }).count <= 1,
            let value = Double(cleaned), value.isFinite
        else { return nil }
        return value
    }

    /// Weight typed by the user: `.` or `,` as the decimal separator, surrounding spaces ignored. Empty or unparsable
    /// text is nil (clears the field); negatives clamp to 0; at most 2 decimals. Plain decimals only (no exponent or
    /// hex), and a value above ``maxWeight`` is nil.
    public static func parseWeight(_ text: String) -> Double? {
        guard let value = plainDecimal(text), value <= maxWeight else { return nil }
        return (max(0, value) * 100).rounded() / 100
    }

    /// Reps or seconds typed by the user: a whole number ≥ 0. A decimal is rounded; empty text, an exponent, hex or
    /// other unparsable text is nil. Huge values clamp to 1,000,000.
    public static func parseCount(_ text: String) -> Int? {
        guard let value = plainDecimal(text) else { return nil }
        return Int(min(max(0, value.rounded()), 1_000_000))
    }

    /// Field text for a stored weight: `27.5`, `100`; empty for nil.
    public static func weightText(_ weight: Double?) -> String {
        weight.map { WeightFormat.number(max(0, $0)) } ?? ""
    }

    /// Field text for stored reps or seconds; empty for nil.
    public static func countText(_ count: Int?) -> String {
        count.map { String(max(0, $0)) } ?? ""
    }

    /// Field text for a stored duration: `0:30`, `1:20`, `12:05`, `1:00:00`; empty for nil.
    public static func durationText(_ seconds: Int?) -> String {
        seconds.map { ClockFormat.clock(seconds: $0) } ?? ""
    }

    /// The editing buffer of a stored duration, minutes then two-digit seconds without a separator (`90` → `130`,
    /// `30` → `30`); empty for nil. Hours fold into minutes (`3600` → `6000`).
    public static func durationDigits(_ seconds: Int?) -> String {
        guard let seconds else { return "" }
        let total = max(0, seconds)
        let minutes = total / 60
        return minutes == 0 ? "\(total)" : "\(minutes)\(String(format: "%02d", total % 60))"
    }

    /// Digits typed into a Time cell, read like a microwave: the last two are seconds, the rest minutes, normalised
    /// (`190` → 150). Non-digits are dropped; no digits is nil.
    public static func parseDurationDigits(_ text: String) -> Int? {
        let digits = String(text.filter { $0.isASCII && $0.isNumber }.suffix(6))
        guard !digits.isEmpty else { return nil }
        let seconds = Int(digits.suffix(2)) ?? 0
        let minutes = Int(digits.dropLast(2)) ?? 0
        return minutes * 60 + seconds
    }

    /// A Time cell's text as shown (`1:30`, `1:00:00`) or typed back to a duration: colon groups are read as
    /// h:mm:ss / m:ss, anything else as microwave digits. Empty or unparsable text is nil.
    public static func parseDurationText(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count > 1, parts.count <= 3,
            parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return parseDurationDigits(text) }
        return parts.reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }

    /// The live text of a Time cell while typing: digits fill from the right (`1` → `1`, `13` → `13`, `130` → `1:30`,
    /// `1305` → `13:05`). Non-digits are dropped.
    public static func durationEntryText(_ digits: String) -> String {
        let digits = String(digits.filter { $0.isASCII && $0.isNumber }.suffix(6))
        guard digits.count > 2 else { return digits }
        let minutes = Int(digits.dropLast(2)) ?? 0
        return "\(minutes):\(digits.suffix(2))"
    }

    /// The Previous cell text: `60 kg × 8`, `12 reps`, `20 kg × 45 s`; nil when the previous set recorded nothing. A
    /// weight-less column (`showsWeight == false`) drops the weight.
    public static func previousText(_ previous: PreviousSet?, unit: WeightUnit, showsWeight: Bool = true) -> String? {
        guard let previous else { return nil }
        let text = formatSetDetail(
            weight: showsWeight ? previous.weight : nil,
            unit: unit,
            reps: previous.reps,
            durationSeconds: previous.durationSeconds
        )
        return text.isEmpty ? nil : text
    }
}
