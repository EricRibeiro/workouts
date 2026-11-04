//
//  SetRowModel.swift
//  Workouts
//

import Foundation
import WorkoutsKit

/// Plain values a `SetRow` renders (task 2.2a). The set table builds one per set from the engine (or a template or a past
/// workout); the row itself never sees a model object.
struct SetRowModel: Identifiable, Hashable {
    let id: UUID
    /// 1-based position among the exercise's sets; shown for a normal set.
    var number: Int
    var kind: SetKind = .normal
    /// The Previous cell text (`60 kg × 8`), nil when there is none; built by `SetInputFormat.previousText`.
    var previousText: String?
    var weightText: String = ""
    /// The reps field's text, or the duration in seconds when `measure` is `.duration`.
    var repsText: String = ""
    var isChecked: Bool = false
    /// Greyed hints from the template plan; `–` when there is none.
    var weightPlaceholder: String = "–"
    var repsPlaceholder: String = "–"
    var unit: WeightUnit = .kg
    /// Decides the keyboard's weight step (barbells jump by double).
    var weightType: WeightType = .weighted
    var measure: SetInputFormat.Measure = .reps
    /// False for exercises that have no weight column.
    var showsWeight: Bool = true
    /// False in template mode (no history to copy from) and in a past workout.
    var showsPrevious: Bool = true
    /// False in template mode and in a past workout; only the active workout checks sets off.
    var showsCheck: Bool = true
}

/// One focusable cell of a set row. The set table owns a single `@FocusState<SetRowField?>` so the keyboard's Next can move
/// weight → reps → the next row's weight (`SetKeyboard.nextField`, task 2.2b). Defined in the kit so the order is tested there.
typealias SetRowField = SetKeyboard.Field
