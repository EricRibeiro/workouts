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
//   Color.danger          destructive text and icons
//   Color.warmup          warm-up set kind
//   Color.setKindDrop     drop set kind
//   Color.setKindFailure  failure set kind
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
