//
//  ExerciseNameStyle.swift
//  Workouts
//

import SwiftUI

private struct ExerciseNameLineLimit: ViewModifier {
    let isEnabled: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .lineLimit(isEnabled ? (dynamicTypeSize.isAccessibilitySize ? 2 : 1) : nil)
            .truncationMode(.tail)
    }
}

extension View {
    /// Long exercise names truncate instead of wrapping: one line with a tail ellipsis, two at accessibility sizes. VoiceOver
    /// still reads the full text (the text is not changed, only clipped). Pass `false` where the name should wrap.
    func exerciseNameLineLimit(_ isEnabled: Bool = true) -> some View {
        modifier(ExerciseNameLineLimit(isEnabled: isEnabled))
    }
}
