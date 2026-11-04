import Foundation

/// Pure parsing and formatting behind a set row's text fields and labels (task 2.2a). Everything the view shows or
/// commits goes through here so it is tested without a simulator.
public nonisolated enum SetInputFormat {
    /// What the second input column of a set row measures.
    public enum Measure: String, Sendable, Hashable, CaseIterable {
        case reps
        /// Time exercises: whole seconds.
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

    /// Weight typed by the user: `.` or `,` as the decimal separator, surrounding spaces ignored. Empty or unparsable
    /// text is nil (clears the field); negatives clamp to 0; at most 2 decimals.
    public static func parseWeight(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return (max(0, value) * 100).rounded() / 100
    }

    /// Reps or seconds typed by the user: a whole number ≥ 0. A decimal is rounded; empty or unparsable text is nil.
    public static func parseCount(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return Int(min(max(0, value.rounded()), 1_000_000))
    }

    /// Field text for a stored weight: `27.5`, `100`; empty for nil.
    public static func weightText(_ weight: Double?) -> String {
        weight.map { formatWeight(max(0, $0)) } ?? ""
    }

    /// Field text for stored reps or seconds; empty for nil.
    public static func countText(_ count: Int?) -> String {
        count.map { String(max(0, $0)) } ?? ""
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
