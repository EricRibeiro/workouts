import Foundation

/// The exercise rows of the template preview (`workout.md` sections 2 and 3): `N × Name` with the planned values of its
/// sets underneath, and the superset group. Pure over the models; the view only lays it out.
public struct TemplatePreviewRow: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let exerciseID: UUID
    public let name: String
    public let setCount: Int
    public let supersetGroup: Int?
    /// `Warm-up 40 kg × 8 · 3 × 100 kg × 5`; empty when no set has a planned value.
    public let plan: String

    /// `3 × Bench Press`.
    public var title: String { "\(setCount) × \(name)" }

    /// The row's VoiceOver sentence: `3 sets of Bench Press, 3 × 100 kg × 5`.
    public var accessibilityLabel: String {
        let sets = setCount == 1 ? "1 set" : "\(setCount) sets"
        return plan.isEmpty ? "\(sets) of \(name)" : "\(sets) of \(name), \(plan)"
    }

    /// The preview's rows for `template`, in position order.
    public static func rows(for template: Template) -> [TemplatePreviewRow] {
        let exercises = (template.exercises ?? []).sorted {
            $0.position != $1.position ? $0.position < $1.position : $0.id.uuidString < $1.id.uuidString
        }
        return exercises.map { exercise in
            let sets = (exercise.sets ?? []).sorted { $0.position < $1.position }
            return TemplatePreviewRow(
                id: exercise.id,
                exerciseID: exercise.exerciseID,
                name: exercise.exerciseName,
                setCount: sets.count,
                supersetGroup: exercise.supersetGroup,
                plan: planText(sets, unit: exercise.unit)
            )
        }
    }

    /// Consecutive identical sets collapse (`3 × 100 kg × 5`); non-normal kinds are named (`Warm-up 40 kg × 8`); sets
    /// without a planned value are left out.
    public static func planText(_ sets: [TemplateSet], unit: WeightUnit) -> String {
        struct Entry: Equatable {
            var text: String
            var count: Int
        }
        var entries: [Entry] = []
        for set in sets {
            let detail = formatSetDetail(
                weight: set.weight,
                unit: unit,
                reps: set.reps,
                durationSeconds: set.durationSeconds
            )
            guard !detail.isEmpty else { continue }
            let text = set.kind == .normal ? detail : "\(kindName(set.kind)) \(detail)"
            if let last = entries.last, last.text == text {
                entries[entries.count - 1].count += 1
            } else {
                entries.append(Entry(text: text, count: 1))
            }
        }
        return entries.map { $0.count > 1 ? "\($0.count) × \($0.text)" : $0.text }.joined(separator: " · ")
    }

    private static func kindName(_ kind: SetKind) -> String {
        switch kind {
        case .warmup: "Warm-up"
        case .drop: "Drop"
        case .failure: "Failure"
        case .normal: ""
        }
    }
}
