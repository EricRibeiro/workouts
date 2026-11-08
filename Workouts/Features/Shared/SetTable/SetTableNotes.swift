//
//  SetTableNotes.swift
//  Workouts
//

import SwiftUI

/// The sticky note's band under a `SetTable` block's name (PLAN 7.8b): at most ``lineLimit`` lines, then an ellipsis (the
/// full text is in the editor, the exercise detail and the accessibility label). With `onEdit` the whole band is a button
/// that opens the note editor; without it (no block menu) it is plain text.
struct SetTableStickyBand: View {
    /// Lines shown before the tail truncates; the exercise detail and the editor show all of it.
    static let lineLimit = 3

    let text: String
    var identifier: String
    var onEdit: (() -> Void)?

    var body: some View {
        if let onEdit {
            Button(action: onEdit) { band }
                .buttonStyle(.plain)
                .accessibilityLabel("Sticky note: \(text)")
                .accessibilityHint("Edits the note")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier(identifier)
        } else {
            band
                .accessibilityLabel("Sticky note: \(text)")
                .accessibilityIdentifier(identifier)
        }
    }

    private var band: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.primary)
            .lineLimit(Self.lineLimit)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.stickyNote, in: .rect(cornerRadius: Metrics.stickyNoteCornerRadius))
            .contentShape(.rect(cornerRadius: Metrics.stickyNoteCornerRadius))
    }
}

/// The block's own note under its name (secondary text). With `onEdit` it is a button that opens the note editor.
struct SetTableNoteLine: View {
    let text: String
    var identifier: String
    var onEdit: (() -> Void)?

    var body: some View {
        if let onEdit {
            Button(action: onEdit) { line }
                .buttonStyle(.plain)
                .accessibilityLabel("Note: \(text)")
                .accessibilityHint("Edits the note")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier(identifier)
        } else {
            line
                .accessibilityIdentifier(identifier)
        }
    }

    private var line: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
    }
}
