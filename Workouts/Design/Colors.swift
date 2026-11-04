//
//  Colors.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

// The semantic palette lives in `Assets.xcassets/Colors` (light and dark). Xcode generates the
// `Color` symbols from it (`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`):
//
//   Color.ok              green for text and icons on a page surface
//   Color.okFill          green for filled shapes (a checked set); pair with dark text
//   Color.okRow           soft green row tint behind a checked set
//   Color.onOkFill        dark glyph or text on okFill
//   Color.danger          destructive text and icons
//   Color.stickyNote      sticky note band: pale yellow in light, dark warm amber in dark (not a yellow tint at
//                         opacity, which goes olive on black); primary text reads on it in both
//   Color.warmup          warm-up set kind
//   Color.setKindDrop     drop set kind
//   Color.setKindFailure  failure set kind
//   Color.superset1…6     superset group colours (purple, teal, magenta, orange, indigo, olive); each is at least
//                         3:1 against the system and secondary backgrounds in both appearances and is distinct
//                         from the accent blue, ok green, danger red and warm-up amber. Use `Color.superset(_:)`.
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
