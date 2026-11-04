//
//  SetFieldCell.swift
//  Workouts
//

import SwiftUI

/// One number cell of a set row (weight, reps or duration): a centred `TextField` on a filled cell that turns to a tinted fill
/// while focused. Keeps its own text while typing and reports every change as `commit`; the stored `value` wins again whenever it
/// differs from what the text means (Previous tapped, a keyboard step), and the text is normalised when focus leaves.
struct SetFieldCell: View {
    /// The stored value as field text (already normalised, empty when unset).
    let value: String
    let placeholder: String
    let keyboard: UIKeyboardType
    let field: SetRowField
    var focus: FocusState<SetRowField?>.Binding
    let label: String
    let hint: String
    let identifier: String
    /// The text a typed string normalises to (parse, clamp, format); empty when it means nothing.
    let normalize: (String) -> String
    let commit: (String) -> Void

    @State private var text = ""
    @State private var selection: TextSelection?
    @ScaledMetric(relativeTo: .body) private var minHeight = 40.0

    private var isFocused: Bool { focus.wrappedValue == field }

    var body: some View {
        TextField(
            label,
            text: $text,
            selection: $selection,
            prompt: Text(placeholder).foregroundStyle(.tertiary)
        )
        .keyboardType(keyboard)
        .focused(focus, equals: field)
        .multilineTextAlignment(.center)
        .font(.body.monospacedDigit())
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isFocused ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary))
        )
        .contentShape(.rect)
        .onTapGesture { focus.wrappedValue = field }
        .onAppear { text = value }
        .onChange(of: text) { _, newText in
            if normalize(newText) != value { commit(newText) }
        }
        .onChange(of: value) { _, newValue in
            if normalize(text) != newValue { text = newValue }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                // First key replaces the cell's text.
                if !text.isEmpty { selection = TextSelection(range: text.startIndex..<text.endIndex) }
            } else {
                text = normalize(text)
            }
        }
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }
}
