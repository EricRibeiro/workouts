//
//  Colors.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

// The semantic palette lives in `Assets.xcassets/Colors` (the app is dark-only). Xcode generates the
// `Color` symbols from it (`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`):
//
//   Color.ok              lime #C4F861 text accent for text and icons on a page surface
//   Color.okFill          lime #C4F861 for filled shapes (the swatches only; a done set uses `ok`); pair with onOkFill
//   Color.okRow           dark olive #1B2A0A row tint behind a checked set
//   Color.onOkFill        black glyph or text on okFill
//   Color.danger          destructive text and icons
//   Color.onAccent        black label on a filled lime accent shape
//   Color.statDuration, statVolume, statSets, statExercises, statPRs
//                         Finish summary stat values (22pt bold), each at least 3:1 on #1C1C1E and black
//   Color.record          personal-record trophy: system yellow
//   Color.chartBelowGoal  weekly-goal chart bar for a week under the goal: the lime accent at 0.35 alpha
//   Color.warmup          warm-up set kind
//   Color.setKindDrop     drop set kind
//   Color.setKindFailure  failure set kind
//   Color.superset1…6     superset group colours (purple, teal, magenta, orange, indigo, olive); each is at least
//                         3:1 against the system and secondary backgrounds and is distinct from the lime accent,
//                         danger red and warm-up amber. Use `Color.superset(_:)`.
//
// The accent is `AccentColor` (`Color.accentColor`, `.tint`). Everything else is system material.

extension SetKind {
    /// The colour of this kind's set-number letter (W, D, F). Normal sets keep the primary label colour.
    var color: Color {
        switch self {
        case .warmup: .warmup
        case .normal: .primary
        case .drop: .setKindDrop
        case .failure: .setKindFailure
        }
    }
}

extension Color {
    /// Six colours by superset number, wrapping (`workout.md` "Supersets"): the `Superset1…6` asset colours. None of
    /// them is the accent, a set-kind or a check colour.
    /// Shared by the set table's bar and the History detail's.
    static func superset(_ number: Int) -> Color {
        let palette: [Color] = [.superset1, .superset2, .superset3, .superset4, .superset5, .superset6]
        return palette[((number - 1) % palette.count + palette.count) % palette.count]
    }
}
