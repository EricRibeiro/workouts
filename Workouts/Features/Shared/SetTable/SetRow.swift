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
    let onToggleCheck: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var touch = 44.0
    @ScaledMetric(relativeTo: .body) private var labelWidth = 28.0

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
                .fill(model.isChecked ? Color.okFill.opacity(0.22) : .clear)
        )
        .animation(.easeOut(duration: 0.2), value: model.isChecked)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setrow.\(model.id.uuidString)")
    }

    // MARK: Layouts

    private var oneLine: some View {
        HStack(spacing: 8) {
            kindButton
            previousButton
                .frame(maxWidth: .infinity, alignment: .center)
            fields
            checkButton
        }
    }

    private var twoLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                kindButton
                previousButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                fields
                checkButton
            }
        }
    }

    @ViewBuilder
    private var fields: some View {
        if model.showsWeight { weightField }
        repsField
    }

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
        .accessibilityIdentifier("setrow.\(model.id.uuidString).kind")
    }

    @ViewBuilder
    private var previousButton: some View {
        if let previous = model.previousText {
            Button(action: onApplyPrevious) {
                Text(previous)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.tertiary)
                .frame(minHeight: touch)
                .accessibilityLabel("No previous")
                .accessibilityIdentifier("setrow.\(model.id.uuidString).previous")
        }
    }

    private var weightField: some View {
        SetFieldCell(
            value: model.weightText,
            placeholder: model.weightPlaceholder,
            keyboard: .decimalPad,
            field: SetRowField(setID: model.id, column: .weight),
            focus: focus,
            label: "Weight",
            hint: model.unit == .kg ? "Kilograms" : "Pounds",
            identifier: "setrow.\(model.id.uuidString).weight",
            normalize: { SetInputFormat.weightText(SetInputFormat.parseWeight($0)) },
            commit: { onCommitWeight(SetInputFormat.parseWeight($0)) }
        )
    }

    private var repsField: some View {
        SetFieldCell(
            value: model.repsText,
            placeholder: model.repsPlaceholder,
            keyboard: .numberPad,
            field: SetRowField(setID: model.id, column: .reps),
            focus: focus,
            label: model.measure == .duration ? "Duration" : "Reps",
            hint: model.measure == .duration ? "Seconds" : "",
            identifier: "setrow.\(model.id.uuidString).reps",
            normalize: { SetInputFormat.countText(SetInputFormat.parseCount($0)) },
            commit: { onCommitReps(SetInputFormat.parseCount($0)) }
        )
    }

    private var checkButton: some View {
        Button(action: onToggleCheck) {
            Image(systemName: "checkmark")
                .font(.body.bold())
                .foregroundStyle(model.isChecked ? Color.black.opacity(0.85) : Color.secondary)
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
        .accessibilityAddTraits(.isToggle)
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
                            onToggleCheck: { update(row.id) { $0.isChecked.toggle() } }
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
                SetRowModel(id: UUID(), number: 8),
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
