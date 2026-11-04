//
//  FinishSummaryView.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// A finished workout's summary as a presentable item (`FinishSummary` itself is not `Identifiable`).
struct FinishSummaryItem: Identifiable {
    let id = UUID()
    let summary: FinishSummary
}

/// The centred summary sheet shown after Finish (`active-workout.md` section 3): a check, "Workout complete", the
/// workout's ordinal, and Fitness-style coloured values. Done sits in the Close slot; nothing is bottom-anchored.
struct FinishSummaryView: View {
    let summary: FinishSummary

    @Environment(\.dismiss) private var dismiss
    /// Flips once on appear when the workout set a record; `levelChange` plays then.
    @State private var celebrated = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }
                .listRowBackground(Color.clear)

                Section {
                    stat(
                        "Duration",
                        Self.durationText(summary.duration),
                        spoken: Self.spokenDuration(summary.duration),
                        tint: .orange
                    )
                    .accessibilityIdentifier("summary.duration")
                    stat(
                        "Volume",
                        HistoryList.volumeText(summary.volume, unit: summary.volumeUnit),
                        spoken: Self.spokenVolume(summary.volume, unit: summary.volumeUnit),
                        tint: .blue
                    )
                    .accessibilityIdentifier("summary.volume")
                    stat("Sets", "\(summary.setCount)", spoken: Self.counted(summary.setCount, "set"), tint: .green)
                        .accessibilityIdentifier("summary.sets")
                    stat(
                        "Exercises",
                        "\(summary.exerciseCount)",
                        spoken: Self.counted(summary.exerciseCount, "exercise"),
                        tint: .cyan
                    )
                    .accessibilityIdentifier("summary.exercises")
                    stat("PRs", "\(summary.prCount)", spoken: Self.counted(summary.prCount, "PR"), tint: .pink)
                        .accessibilityIdentifier("summary.prs")
                }

                ForEach(summary.prs, id: \.exerciseID) { exercise in
                    Section {
                        // TODO(4.2): link to Records
                        ForEach(Array(exercise.records.enumerated()), id: \.offset) { _, record in
                            recordRow(record)
                        }
                    } header: {
                        Text(exercise.exerciseName)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Done")
                        .accessibilityIdentifier("summary.done")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("screen.finishSummary")
        .sensoryFeedback(.levelChange, trigger: celebrated)
        .onAppear {
            if summary.prCount > 0 { celebrated = true }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.ok)
                .accessibilityHidden(true)
            Text("Workout complete")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if summary.workoutNumber >= 1 {
                Text("Your \(Self.ordinal(summary.workoutNumber)) workout")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ title: String, _ value: String, spoken: String, tint: Color) -> some View {
        LabeledContent {
            Text(value)
                .font(.title2.bold())
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(tint)
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(spoken)")
    }

    private func recordRow(_ record: PersonalRecord) -> some View {
        let text = Self.recordText(record, unit: summary.volumeUnit)
        return Label {
            Text(text)
        } icon: {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.yellow)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Personal record, \(text)")
    }

    // MARK: Text

    /// The ordinal in "Your 615th workout": `615th`.
    static func ordinal(_ number: Int) -> String {
        let format = NumberFormatter()
        format.locale = Locale(identifier: "en_US")
        format.numberStyle = .ordinal
        return format.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    /// `1h 12min`, `45min`, `<1min`: the same text History shows.
    static func durationText(_ duration: TimeInterval) -> String {
        HistoryList.durationText(seconds: Int(duration))
    }

    /// `42 minutes`, `1 hour, 12 minutes`; seconds when under a minute.
    static func spokenDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds < 60 ? [.seconds] : [.hours, .minutes]
        return Duration.seconds(seconds).formatted(.units(allowed: units, width: .wide))
    }

    static func spokenVolume(_ volume: Double, unit: WeightUnit) -> String {
        let name = unit == .kg ? "kilograms" : "pounds"
        return HistoryList.volumeText(volume, unit: unit)
            .replacingOccurrences(of: " \(unit.rawValue)", with: " \(name)")
    }

    static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    /// One record line: `Estimated 1RM 245 lb`, `Heaviest 225 lb`, `Best set 1,125 lb`, `Longest 1:30`, `12 reps at 135 lb`.
    static func recordText(_ record: PersonalRecord, unit: WeightUnit) -> String {
        let weight = "\(SetInputFormat.weightText(record.weight)) \(unit.rawValue)"
        switch record.kind {
        case .e1rm: return "Estimated 1RM \(SetInputFormat.weightText(record.value)) \(unit.rawValue)"
        case .heaviest: return "Heaviest \(weight)"
        case .bestVolumeSet: return "Best set \(HistoryList.volumeText(record.value, unit: unit))"
        case .longestDuration: return "Longest \(ElapsedFormat.string(seconds: Int(record.value)))"
        case .repsAtWeight:
            let reps = Int(record.value)
            return "\(reps) \(reps == 1 ? "rep" : "reps") at \(weight)"
        }
    }
}

extension FinishSummary {
    /// A realistic summary for previews and the gallery.
    static var sample: FinishSummary {
        FinishSummary(
            duration: 42 * 60 + 10,
            setCount: 18,
            exerciseCount: 5,
            volume: 15_421,
            volumeUnit: .lb,
            prs: [
                ExercisePRs(
                    exerciseID: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1") ?? UUID(),
                    exerciseName: "Bench Press (Barbell)",
                    records: [
                        PersonalRecord(kind: .e1rm, value: 245, weight: 215, reps: 5),
                        PersonalRecord(kind: .heaviest, value: 225, weight: 225, reps: 3),
                    ]
                ),
                ExercisePRs(
                    exerciseID: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2") ?? UUID(),
                    exerciseName: "Pull Up",
                    records: [PersonalRecord(kind: .repsAtWeight, value: 12, weight: 0, reps: 12)]
                ),
            ],
            prCount: 3,
            workoutNumber: 615,
            uncheckedWithValues: 0,
            uncheckedWithoutValues: 0,
            dialog: .none
        )
    }
}

#Preview("Large") {
    FinishSummaryView(summary: .sample)
        .dynamicTypeSize(.large)
}

#Preview("Accessibility 3") {
    FinishSummaryView(summary: .sample)
        .dynamicTypeSize(.accessibility3)
}
