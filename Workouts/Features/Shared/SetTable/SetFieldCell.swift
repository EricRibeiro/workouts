//
//  SetFieldCell.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// One number cell of a set row (weight, reps or duration): a centred `TextField` on a filled cell that turns to a tinted fill
/// while focused. Keeps its own text while typing and reports every change as `commit`; the stored `value` wins again whenever it
/// differs from what the text means (Previous tapped, a keyboard step), and the text is normalised when focus leaves.
struct SetFieldCell: View {
    /// The stored value as field text (already normalised, empty when unset).
    let value: String
    let placeholder: String
    let keyboard: UIKeyboardType
    /// A checked row's cells drop their fill so the values read as plain text (still editable).
    let isChecked: Bool
    /// The row to do now: its cells get the brighter fill; the other unchecked rows stay dim.
    var isNext = false
    let field: SetRowField
    var focus: FocusState<SetRowField?>.Binding
    /// Whether this cell has focus, given by the row: the cell never reads the shared `FocusState` value, so a focus move
    /// re-renders only the two cells it concerns.
    let isFocused: Bool
    let label: String
    let hint: String
    let identifier: String
    /// The text a typed string normalises to (parse, clamp, format); empty when it means nothing.
    let normalize: (String) -> String
    let commit: (String) -> Void
    /// A Time cell's entry mode: while focused, every text change is reshaped (digits fill from the right, `130` → `1:30`)
    /// and focusing re-expresses the stored text as that entry text. nil for weight and reps.
    var entry: Entry?
    /// A VoiceOver swipe up / down: the same step as the keyboard's − / + keys.
    let adjust: (SetKeyboard.Direction) -> Void

    @State private var text = ""
    @State private var selection: TextSelection?
    @ScaledMetric(relativeTo: .body) private var minHeight = 44.0
    /// The width the cell asks for when `SetRow`'s `ViewThatFits` measures it. Fixed (it scales with Dynamic Type only), so the
    /// one-line or two-line choice cannot follow what is typed: a text-sized ideal width flipped the branch mid-typing,
    /// rebuilt the field and dropped focus. The cell still grows to fill the row.
    @ScaledMetric(relativeTo: .body) private var idealWidth = 56.0

    struct Entry {
        let reshape: (String) -> String
        let focusText: (String) -> String
    }

    private var fill: AnyShapeStyle {
        if isFocused { return AnyShapeStyle(Color.accentColor.opacity(0.2)) }
        if isChecked { return AnyShapeStyle(Color.clear) }
        return isNext ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.quaternary)
    }

    var body: some View {
        TextField(
            label,
            text: $text,
            selection: $selection,
            prompt: Text(placeholder).foregroundStyle(Color.setSecondaryText)
        )
        .keyboardType(keyboard)
        .focused(focus, equals: field)
        .multilineTextAlignment(.center)
        .font(.system(.body, design: .rounded, weight: .medium).monospacedDigit())
        .lineLimit(1)
        .frame(idealWidth: idealWidth, maxWidth: .infinity, minHeight: minHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(fill)
        )
        .contentShape(.rect)
        .onTapGesture { focus.wrappedValue = field }
        .onAppear { text = value }
        .onChange(of: text) { _, newText in
            if isFocused, let entry {
                let shaped = entry.reshape(newText)
                if shaped != newText {
                    text = shaped
                    return
                }
            }
            if normalize(newText) != value { commit(newText) }
        }
        .onChange(of: value) { _, newValue in
            if normalize(text) != newValue { text = newValue }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                if let entry { text = entry.focusText(text) }
                // First key replaces the cell's text.
                if !text.isEmpty { selection = TextSelection(range: text.startIndex..<text.endIndex) }
            } else {
                text = normalize(text)
            }
        }
        .accessibilityLabel(label)
        // An empty field would otherwise report its placeholder (the Previous value) as if it were typed.
        .accessibilityValue(text.isEmpty ? "Empty" : (entry == nil ? text : normalize(text)))
        .accessibilityHint(hint)
        .accessibilityAdjustableAction { adjust($0 == .increment ? .increment : .decrement) }
        .accessibilityIdentifier(identifier)
    }
}

extension Color {
    /// Secondary text on a set cell (the unchecked `.quaternary` fill or the checked `okRow`). `.secondary` is only 3.2-3.3:1
    /// there in light mode; 70 % of the primary label colour is 7.7-8.2:1 in light and 5.9-9.3:1 in dark (WCAG needs 4.5).
    static let setSecondaryText = Color.primary.opacity(0.7)
}
