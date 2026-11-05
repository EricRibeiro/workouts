//
//  ExerciseRecordsView.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// How a record reads on screen (`docs/port/screens/exercises.md` section 2, "Records tab").
enum RecordFormat {
    static func title(_ record: ExerciseRecord, weightType: WeightType) -> String {
        switch record.kind {
        case .e1rm: "Estimated 1RM"
        case .heaviest: weightType.category == .assisted ? "Least assistance" : "Heaviest weight"
        case .bestVolumeSet: "Best set volume"
        case .longestDuration: "Longest duration"
        case .repsAtWeight: weightType.category == .assisted ? "Reps at assistance" : "Reps at weight"
        }
    }

    /// `225 lb`, `Bodyweight` for zero.
    static func weight(_ value: Double, unit: WeightUnit) -> String {
        value > 0 ? WeightFormat.groupedText(value, unit: unit) : "Bodyweight"
    }

    static func value(_ record: ExerciseRecord, unit: WeightUnit) -> String {
        switch record.kind {
        case .e1rm, .heaviest, .bestVolumeSet: WeightFormat.groupedText(record.value, unit: unit)
        case .longestDuration: ClockFormat.clock(seconds: Int(record.value))
        case .repsAtWeight: "\(record.reps) \(record.reps == 1 ? "rep" : "reps")"
        }
    }

    /// The qualifier under the value: the holding set of a volume record, the confidence note of an e1RM.
    static func detail(_ record: ExerciseRecord, unit: WeightUnit) -> String? {
        switch record.kind {
        case .bestVolumeSet: "\(weight(record.weight, unit: unit)) × \(record.reps)"
        case .e1rm where record.lowConfidence: "from over 12 reps"
        default: nil
        }
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// The Records segment: the headline records as rows, then the reps-at-weight table. Each headline row opens the
/// workout that set it in the History tab; the embedded pane (over the active workout's cover) and the reps-at-weight
/// table stay plain text.
struct ExerciseRecordsView: View {
    let records: [ExerciseRecord]
    let weightType: WeightType
    let unit: WeightUnit
    var embedded = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppNavigation.self) private var navigation: AppNavigation?

    private var headline: [ExerciseRecord] { records.filter { $0.kind != .repsAtWeight } }
    private var table: [ExerciseRecord] { records.filter { $0.kind == .repsAtWeight } }
    private var assisted: Bool { weightType.category == .assisted }

    var body: some View {
        if records.isEmpty {
            Text("No records yet. Log a workout with this exercise to set some.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("exerciseDetail.records.empty")
        } else {
            VStack(alignment: .leading, spacing: 20) {
                if !headline.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(headline.enumerated()), id: \.element.kind) { index, record in
                            if index > 0 { Divider() }
                            openableRow(record)
                        }
                    }
                    .detailCardStyle()
                }
                if !table.isEmpty { repsTable }
            }
        }
    }

    @ViewBuilder
    private func openableRow(_ record: ExerciseRecord) -> some View {
        if !embedded, let navigation {
            Button {
                navigation.openWorkout(record.workoutID)
            } label: {
                row(record, opens: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exerciseDetail.records.\(record.kind.rawValue)")
        } else {
            row(record, opens: false)
                .accessibilityIdentifier("exerciseDetail.records.\(record.kind.rawValue)")
        }
    }

    private func row(_ record: ExerciseRecord, opens: Bool) -> some View {
        let title = RecordFormat.title(record, weightType: weightType)
        let value = RecordFormat.value(record, unit: unit)
        let detail = RecordFormat.detail(record, unit: unit)
        let date = RecordFormat.date(record.time)
        let spoken = [title, value, detail, date].compactMap { $0 }.joined(separator: ", ")
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(date).font(.footnote).foregroundStyle(.secondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if opens {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint(opens ? "Opens the workout from \(date) in History" : "")
    }

    @ViewBuilder
    private var repsTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RecordFormat.title(table[0], weightType: weightType))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(table.enumerated()), id: \.offset) { index, record in
                        if index > 0 { Divider() }
                        repsRowStacked(record, index: index)
                    }
                }
                .detailCardStyle()
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text(assisted ? "Assistance" : "Weight")
                        Text("Reps").gridColumnAlignment(.trailing)
                        Text("Date").gridColumnAlignment(.trailing)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    Divider()
                    ForEach(Array(table.enumerated()), id: \.offset) { index, record in
                        repsRow(record, index: index)
                    }
                }
                .detailCardStyle()
            }
        }
    }

    private func spokenReps(_ record: ExerciseRecord) -> String {
        [
            RecordFormat.weight(record.weight, unit: unit),
            RecordFormat.value(record, unit: unit),
            RecordFormat.date(record.time),
        ].joined(separator: ", ")
    }

    private func repsRow(_ record: ExerciseRecord, index: Int) -> some View {
        GridRow {
            Text(RecordFormat.weight(record.weight, unit: unit)).monospacedDigit()
            Text("\(record.reps)").monospacedDigit().foregroundStyle(.tint).fontWeight(.semibold)
            Text(RecordFormat.date(record.time)).foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenReps(record))
        .accessibilityIdentifier("exerciseDetail.records.repsAtWeight.\(index)")
    }

    private func repsRowStacked(_ record: ExerciseRecord, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(RecordFormat.weight(record.weight, unit: unit)), \(RecordFormat.value(record, unit: unit))")
                .font(.body)
            Text(RecordFormat.date(record.time)).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenReps(record))
        .accessibilityIdentifier("exerciseDetail.records.repsAtWeight.\(index)")
    }
}

extension View {
    /// The grouped-card surface of the exercise detail (same shape as the dashboard cards).
    func detailCardStyle() -> some View {
        padding(.horizontal)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}
