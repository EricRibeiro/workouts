//
//  SetHaptics.swift
//  Workouts
//

import SwiftUI

/// The logging screen's haptics (task 2.2b, `DECISIONS.md` "Haptics"), as `.sensoryFeedback` mapped from engine-observable
/// values. Each parameter is a value that changes when the event happens; a constant never fires, so a caller passes only
/// the ones it can observe yet and later tasks feed the rest (2.4 destructive confirm and minimise, 2.5 rest end, PR).
///
/// - `checkedSetCount`: sets checked in the workout; fires `.impact(weight: .light)` only when it goes up, not on uncheck.
/// - `restEndCount`: bumps when a rest runs out; `.success`.
/// - `recordCount`: bumps when a set sets a personal record; `.levelChange`.
/// - `destructiveConfirmCount`: bumps when a destructive confirmation is shown; `.warning`.
/// - `minimiseToggleCount`: bumps on minimise and restore; `.selection`.
struct SetHaptics: ViewModifier {
    var checkedSetCount = 0
    var restEndCount = 0
    var recordCount = 0
    var destructiveConfirmCount = 0
    var minimiseToggleCount = 0

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.impact(weight: .light), trigger: checkedSetCount) { old, new in new > old }
            .sensoryFeedback(.success, trigger: restEndCount)
            .sensoryFeedback(.levelChange, trigger: recordCount)
            .sensoryFeedback(.warning, trigger: destructiveConfirmCount)
            .sensoryFeedback(.selection, trigger: minimiseToggleCount)
    }
}

extension View {
    /// Applies the workout haptics; see `SetHaptics`.
    func setHaptics(
        checkedSetCount: Int = 0,
        restEndCount: Int = 0,
        recordCount: Int = 0,
        destructiveConfirmCount: Int = 0,
        minimiseToggleCount: Int = 0
    ) -> some View {
        modifier(
            SetHaptics(
                checkedSetCount: checkedSetCount,
                restEndCount: restEndCount,
                recordCount: recordCount,
                destructiveConfirmCount: destructiveConfirmCount,
                minimiseToggleCount: minimiseToggleCount
            )
        )
    }
}
