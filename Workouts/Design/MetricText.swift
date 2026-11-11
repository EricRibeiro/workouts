//
//  MetricText.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// A metric the way Fitness sets one: rounded medium digits with the unit in small caps, glued to the value and in the
/// same colour ("311CAL", "1H 5MIN"). Takes the already formatted string ("22,318 lb", "40min") and restyles its letter
/// runs; the caller sets the colour with `foregroundStyle`.
struct MetricText: View {
    private let text: String
    private let style: Font.TextStyle

    init(_ text: String, style: Font.TextStyle = .title2) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(attributed)
            .accessibilityLabel(text)
    }

    private var attributed: AttributedString {
        let number = Font.system(style, design: .rounded, weight: .medium)
        let unit = number.smallCaps()
        var result = AttributedString()
        for piece in MetricPieces.split(text) {
            var part = AttributedString(piece.isUnit ? piece.text.lowercased() : piece.text)
            part.font = piece.isUnit ? unit : number
            result += part
        }
        return result
    }
}
