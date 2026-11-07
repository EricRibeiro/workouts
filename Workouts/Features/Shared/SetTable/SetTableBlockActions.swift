//
//  SetTableBlockActions.swift
//  Workouts
//

import Foundation

/// The per-exercise header menu of a `SetTable` (task 3.6): what each entry does, supplied by the owner. Every closure takes the
/// block's `SetTableSection.id`. The table's `blockActions` is optional; `nil` means no menu. `addWarmups`, `updateRest`,
/// `remove`, `replace`, `superset` and `preferences` are optional entries: an owner that leaves one nil does not get that
/// entry (the past-workout editor offers only the two notes).
struct SetTableBlockActions {
    /// Note… (the block's note, kept with the template or workout).
    var note: (UUID) -> Void
    /// Sticky Note… (the exercise's own note, shown in every template).
    var stickyNote: (UUID) -> Void
    /// Add Warm-up Sets (not offered while nil).
    var addWarmups: ((UUID) -> Void)?
    /// Update Rest Timer… (not offered while nil).
    var updateRest: ((UUID) -> Void)?
    /// Remove Exercise (the owner confirms first) (not offered while nil).
    var remove: ((UUID) -> Void)?
    /// Replace Exercise… (not offered while nil).
    var replace: ((UUID) -> Void)?
    /// Create / Edit Superset… (not offered while nil).
    var superset: ((UUID) -> Void)?
    /// Preferences (unit, bar) (not offered while nil).
    var preferences: ((UUID) -> Void)?
}
