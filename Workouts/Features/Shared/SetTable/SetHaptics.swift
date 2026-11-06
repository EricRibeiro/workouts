//
//  SetHaptics.swift
//  Workouts
//

import SwiftUI

/// The logging screen's haptics (task 2.2b, `DECISIONS.md` "Haptics"), as `.sensoryFeedback` mapped from engine-observable
/// values. Each parameter is a value that changes when the event happens; a constant never fires, so a caller passes only
/// the ones it can observe yet and later tasks feed the rest (2.4 minimise, 2.5 rest end, PR). Destructive confirmations
/// are not here: each screen that confirms one owns a `.sensoryFeedback(.warning, trigger:)` on a view that outlives it.
///
/// - `checkedSetCount`: sets checked in the workout; fires `.impact(weight: .light)` only when it goes up, not on uncheck.
/// - `restEndCount`: bumps when a rest runs out; `.success`. The live owners are `RestExpiryWatcher` (cover) and
///   `ResumeControl` (cover closed).
/// - `recordCount`: bumps when a set sets a personal record; `.levelChange`.
/// - `minimiseToggleCount`: bumps on minimise and restore; `.selection`.
struct SetHaptics: ViewModifier {
    var checkedSetCount = 0
    var restEndCount = 0
    var recordCount = 0
    var minimiseToggleCount = 0

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.impact(weight: .light), trigger: checkedSetCount) { old, new in new > old }
            .sensoryFeedback(.success, trigger: restEndCount)
            .sensoryFeedback(.levelChange, trigger: recordCount)
            .sensoryFeedback(.selection, trigger: minimiseToggleCount)
    }
}

extension View {
    /// Applies the workout haptics; see `SetHaptics`.
    func setHaptics(
        checkedSetCount: Int = 0,
        restEndCount: Int = 0,
        recordCount: Int = 0,
        minimiseToggleCount: Int = 0
    ) -> some View {
        modifier(
            SetHaptics(
                checkedSetCount: checkedSetCount,
                restEndCount: restEndCount,
                recordCount: recordCount,
                minimiseToggleCount: minimiseToggleCount
            )
        )
    }
}
