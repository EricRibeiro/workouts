//
//  SetRow.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// One set of the set table (task 2.2a): set label · Previous · weight · reps (or duration) · check.
///
/// Takes plain values and closures, no engine. The label shows the set number, or `W` / `D` / `F` in the kind's colour with no
/// pill; tapping it cycles the kind. Tapping Previous asks for it to be copied into the row. Every field commit passes the
/// parsed value, and the cells share one `FocusState` owned by the table so the keyboard can step between them.
///
/// One line normally; the cells stack in two lines at accessibility sizes or whenever the line does not fit.
struct SetRow: View {
    let model: SetRowModel
    var focus: FocusState<SetRowField?>.Binding
    let onCycleKind: () -> Void
    let onApplyPrevious: () -> Void
    let onCommitWeight: (Double?) -> Void
    /// Reps, or seconds for a duration row.
    let onCommitReps: (Int?) -> Void
    /// Returns `false` when the check was refused (nothing to record); the row then wiggles, buzzes and rings red.
    let onToggleCheck: () -> Bool
    /// The VoiceOver "Delete set" action. Attached to the kind and check buttons, not to the row: the row is a `.contain`
    /// container that VoiceOver never focuses, so an action on it is not offered anywhere (A11Y-4).
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var touch = 44.0
    @ScaledMetric(relativeTo: .body) private var labelWidth = 28.0
    @State private var refusedCount = 0
    @State private var showsRefusal = false

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                twoLine
            } else {
                ViewThatFits(in: .horizontal) {
                    oneLine
                    twoLine
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(model.isChecked ? Color.okRow : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.danger, lineWidth: 2)
                .opacity(showsRefusal ? 1 : 0)
                .allowsHitTesting(false)
        )
        .sensoryFeedback(.error, trigger: refusedCount)
        // Clears the red ring 400 ms after the latest refusal: each new refusal cancels and restarts this task, and the row
        // going away cancels it too.
        .task(id: refusedCount) {
            guard showsRefusal else { return }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            withAnimation(.easeOut(duration: 0.2)) { showsRefusal = false }
        }
        .animation(.easeOut(duration: 0.2), value: model.isChecked)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SetInputFormat.setAccessibilityLabel(number: model.number, kind: model.kind))
        .accessibilityIdentifier("setrow.\(model.id.uuidString)")
    }

    // MARK: Layouts

    private var oneLine: some View {
        HStack(spacing: 8) {
            kindButton
            if model.showsPrevious {
                previousButton
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            fields
            if model.showsCheck { checkButton }
        }
    }

    /// Previous (when the row has one) on the first line, the cells and check on the second. A row with no Previous column
    /// (template editor, past editor) has nothing for a first line to carry, so label, cells and check share one line.
    /// With a Previous line the column header is gone at accessibility sizes, so each cell carries its own caption (unit,
    /// Reps / Time); without one the table keeps its header over the single line.
    @ViewBuilder
    private var twoLine: some View {
        if model.showsPrevious {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    kindButton
                    previousButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    fields
                    if model.showsCheck { checkButton }
                }
            }
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                kindButton
                fields
                if model.showsCheck { checkButton }
            }
        }
    }

    @ViewBuilder
    private var fields: some View {
        if model.showsWeight { weightField }
        repsField
    }

    /// The unit of the weight cell; the stacked layout has no column header to say so.
    private var weightCaption: String { model.unit.rawValue }

    private var repsCaption: String { model.measure == .duration ? "Time" : "Reps" }

    // MARK: Cells

    private var kindButton: some View {
        Button(action: onCycleKind) {
            Text(SetInputFormat.setLabel(number: model.number, kind: model.kind))
                .font(.headline.monospacedDigit())
                .foregroundStyle(model.kind.color)
                .frame(minWidth: labelWidth, minHeight: touch)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SetInputFormat.setAccessibilityLabel(number: model.number, kind: model.kind))
        .accessibilityHint("Changes the set type")
        .accessibilityAction(named: "Delete set", onDelete)
        .accessibilityIdentifier("setrow.\(model.id.uuidString).kind")
    }

    @ViewBuilder
    private var previousButton: some View {
        if let previous = model.previousText {
            Button(action: onApplyPrevious) {
                Text(previous)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.setSecondaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.8)
                    .frame(minHeight: touch)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous \(previous)")
            .accessibilityHint("Copies it into this set")
            .accessibilityIdentifier("setrow.\(model.id.uuidString).previous")
        } else {
            Text("–")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minHeight: touch)
                .accessibilityLabel("No previous")
                .accessibilityIdentifier("setrow.\(model.id.uuidString).previous")
        }
    }

    private var weightField: some View {
        captioned(weightCaption) { weightCell }
    }

    private var repsField: some View {
        captioned(repsCaption) { repsCell }
    }

    /// In the stacked layout (accessibility sizes, with a Previous line) a small caption sits over the cell, since the column
    /// header is dropped there. Rows without Previous keep the table's column header instead (`SetTable.block`). Hidden from
    /// VoiceOver: the cell already says "Weight" / "Reps" and carries the unit in its hint.
    @ViewBuilder
    private func captioned(_ caption: String, @ViewBuilder cell: () -> some View) -> some View {
        if dynamicTypeSize.isAccessibilitySize && model.showsPrevious {
            VStack(spacing: 2) {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Color.setSecondaryText)
                    .lineLimit(1)
                    .accessibilityHidden(true)
                cell()
            }
        } else {
            cell()
        }
    }

    private var weightCell: some View {
        SetFieldCell(
            value: model.weightText,
            placeholder: model.weightPlaceholder,
            keyboard: .decimalPad,
            isChecked: model.isChecked,
            field: SetRowField(setID: model.id, column: .weight),
            focus: focus,
            label: "Weight",
            hint: model.unit == .kg ? "Kilograms" : "Pounds",
            identifier: "setrow.\(model.id.uuidString).weight",
            normalize: { SetInputFormat.weightText(SetInputFormat.parseWeight($0)) },
            commit: { onCommitWeight(SetInputFormat.parseWeight($0)) },
            adjust: { direction in
                let text = SetKeyboard.stepped(
                    model.weightText,
                    column: .weight,
                    direction: direction,
                    unit: model.unit,
                    weightType: model.weightType,
                    placeholder: model.weightPlaceholder
                )
                onCommitWeight(SetInputFormat.parseWeight(text))
            }
        )
    }

    private var repsCell: some View {
        SetFieldCell(
            value: model.repsText,
            placeholder: model.repsPlaceholder,
            keyboard: .numberPad,
            isChecked: model.isChecked,
            field: SetRowField(setID: model.id, column: .reps),
            focus: focus,
            label: model.measure == .duration ? "Duration" : "Reps",
            hint: model.measure == .duration ? "Seconds" : "",
            identifier: "setrow.\(model.id.uuidString).reps",
            normalize: { SetInputFormat.countText(SetInputFormat.parseCount($0)) },
            commit: { onCommitReps(SetInputFormat.parseCount($0)) },
            adjust: { direction in
                let text = SetKeyboard.stepped(
                    model.repsText,
                    column: .reps,
                    direction: direction,
                    unit: model.unit,
                    weightType: model.weightType,
                    placeholder: model.repsPlaceholder
                )
                onCommitReps(SetInputFormat.parseCount(text))
            }
        )
    }

    private func toggleCheck() {
        guard !onToggleCheck() else { return }
        refusedCount += 1
        showsRefusal = true
        AccessibilityNotification.Announcement("Enter weight and reps first").post()
    }

    /// Done: dark on the green fill. Not done: `.secondary` on `.quaternary`, so a column of unchecked sets does not read as
    /// a column of done ones; the green fill is the one strong state. No new tint.
    private var checkGlyphStyle: AnyShapeStyle {
        model.isChecked ? AnyShapeStyle(Color.onOkFill) : AnyShapeStyle(.secondary)
    }

    private var checkButton: some View {
        Button(action: toggleCheck) {
            Image(systemName: "checkmark")
                .font(.body.bold())
                .foregroundStyle(checkGlyphStyle)
                .symbolEffect(.wiggle, value: refusedCount)
                .frame(width: touch, height: touch)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(model.isChecked ? AnyShapeStyle(Color.okFill) : AnyShapeStyle(.quaternary))
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mark set done")
        .accessibilityValue(model.isChecked ? "Done" : "Not done")
        // Not `.disabled`: a refused tap must still reach `toggleCheck` so it wiggles, buzzes and announces itself.
        .accessibilityHint(model.isChecked || model.canCheck ? "" : "Enter weight and reps first")
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction(named: "Delete set", onDelete)
        .accessibilityIdentifier("setrow.\(model.id.uuidString).check")
    }
}

#if DEBUG
    /// A small interactive stack of rows (every kind, checked, empty with placeholders, duration) for previews and the gallery
    /// entry `SetRow`. Edits stay in local state; nothing is persisted.
    struct SetRowDemo: View {
        @State private var rows = SetRowDemo.sampleRows
        @FocusState private var focus: SetRowField?

        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        SetRow(
                            model: row,
                            focus: $focus,
                            onCycleKind: { update(row.id) { $0.kind = SetInputFormat.nextKind(after: $0.kind) } },
                            onApplyPrevious: { applyPrevious(row.id) },
                            onCommitWeight: { value in
                                update(row.id) { $0.weightText = SetInputFormat.weightText(value) }
                            },
                            onCommitReps: { value in update(row.id) { $0.repsText = SetInputFormat.countText(value) } },
                            onToggleCheck: {
                                update(row.id) { $0.isChecked.toggle() }
                                return true
                            },
                            onDelete: { rows.removeAll { $0.id == row.id } }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 16)
            }
            .accessibilityIdentifier("screen.setRowDemo")
            .setKeyboardToolbar(
                step: { direction in stepFocused(direction) },
                previous: { if let field = focus { applyPrevious(field.setID) } },
                next: { focusNext() },
                done: { focus = nil }
            )
            .setHaptics(checkedSetCount: rows.filter(\.isChecked).count)
        }

        private func stepFocused(_ direction: SetKeyboard.Direction) {
            guard let field = focus, let row = rows.first(where: { $0.id == field.setID }) else { return }
            switch field.column {
            case .weight:
                let text = SetKeyboard.stepped(
                    row.weightText,
                    column: .weight,
                    direction: direction,
                    unit: row.unit,
                    weightType: row.weightType
                )
                update(row.id) { $0.weightText = text }
            case .reps:
                let text = SetKeyboard.stepped(
                    row.repsText,
                    column: .reps,
                    direction: direction,
                    unit: row.unit,
                    weightType: row.weightType
                )
                update(row.id) { $0.repsText = text }
            }
        }

        private func focusNext() {
            guard let field = focus else { return }
            let weightless = Set(rows.filter { !$0.showsWeight }.map(\.id))
            focus = SetKeyboard.nextField(after: field, in: rows.map(\.id), weightlessSetIDs: weightless)
        }

        private func update(_ id: UUID, _ change: (inout SetRowModel) -> Void) {
            guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
            change(&rows[index])
            // Stands in for the engine's rule: something typed, or a placeholder that checking would fill in.
            let row = rows[index]
            rows[index].canCheck = !row.repsText.isEmpty || row.repsPlaceholder != "–"
        }

        private func applyPrevious(_ id: UUID) {
            update(id) { row in
                guard let previous = SetRowDemo.previousValues[row.number] else { return }
                row.weightText = previous.weight
                row.repsText = previous.reps
            }
        }

        private static let previousValues: [Int: (weight: String, reps: String)] = [
            1: ("60", "8"), 2: ("40", "10"), 3: ("50", "12"), 4: ("62.5", "6"), 5: ("60", "8"),
            6: ("62.5", "8"), 7: ("10", "45"),
        ]

        static var sampleRows: [SetRowModel] {
            [
                SetRowModel(
                    id: UUID(),
                    number: 1,
                    previousText: "60 kg × 8",
                    weightText: "60",
                    repsText: "8"
                ),
                SetRowModel(
                    id: UUID(),
                    number: 2,
                    kind: .warmup,
                    previousText: "40 kg × 10",
                    weightText: "40",
                    repsText: "10"
                ),
                SetRowModel(
                    id: UUID(),
                    number: 3,
                    kind: .drop,
                    previousText: "50 kg × 12",
                    weightText: "50",
                    repsText: "12"
                ),
                SetRowModel(
                    id: UUID(),
                    number: 4,
                    kind: .failure,
                    previousText: "62.5 kg × 6",
                    weightText: "62.5",
                    repsText: "6"
                ),
                SetRowModel(
                    id: UUID(),
                    number: 5,
                    previousText: "60 kg × 8",
                    weightText: "60",
                    repsText: "8",
                    isChecked: true
                ),
                SetRowModel(
                    id: UUID(),
                    number: 6,
                    previousText: "62.5 kg × 8",
                    weightPlaceholder: "62.5",
                    repsPlaceholder: "8"
                ),
                SetRowModel(
                    id: UUID(),
                    number: 7,
                    previousText: "10 kg × 45 s",
                    weightText: "10",
                    repsText: "45",
                    weightPlaceholder: "10",
                    repsPlaceholder: "60",
                    measure: .duration
                ),
                SetRowModel(id: UUID(), number: 8, canCheck: false),
            ]
        }
    }

    #Preview("Large") {
        SetRowDemo()
            .dynamicTypeSize(.large)
    }

    #Preview("Accessibility 3") {
        SetRowDemo()
            .dynamicTypeSize(.accessibility3)
    }
#endif
