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

/// Pushes an exercise's detail on the Records segment from a PR row.
struct ExerciseRecordsRoute: Hashable {
    let exerciseID: UUID
}

/// The centred summary sheet shown after Finish (`active-workout.md` section 3): a check, "Workout complete", the
/// workout's ordinal, and white `MetricText` stats (the PR count is gold when there is a record). Done sits in the Close slot; nothing is bottom-anchored.
struct FinishSummaryView: View {
    let summary: FinishSummary

    @Environment(\.dismiss) private var dismiss
    @Environment(ExerciseStore.self) private var store: ExerciseStore?
    /// Flips once on appear; the one haptic plays then (`levelChange` for a record, `success` otherwise).
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
                        spoken: FitnessFormat.spokenDuration(seconds: summary.duration)
                    )
                    .accessibilityIdentifier("summary.duration")
                    stat(
                        "Volume",
                        HistoryList.volumeText(summary.volume, unit: summary.volumeUnit),
                        spoken: Self.spokenVolume(summary.volume, unit: summary.volumeUnit)
                    )
                    .accessibilityIdentifier("summary.volume")
                    stat("Sets", "\(summary.setCount)", spoken: Self.counted(summary.setCount, "set"))
                        .accessibilityIdentifier("summary.sets")
                    stat(
                        "Exercises",
                        "\(summary.exerciseCount)",
                        spoken: Self.counted(summary.exerciseCount, "exercise")
                    )
                    .accessibilityIdentifier("summary.exercises")
                    stat(
                        "PRs",
                        "\(summary.prCount)",
                        spoken: Self.counted(summary.prCount, "PR"),
                        tint: summary.prCount > 0 ? Color.record : Color.primary
                    )
                    .accessibilityIdentifier("summary.prs")
                }

                ForEach(summary.prs, id: \.exerciseID) { exercise in
                    Section {
                        ForEach(Array(exercise.records.enumerated()), id: \.offset) { _, record in
                            recordRow(record, exerciseID: exercise.exerciseID)
                        }
                    } header: {
                        Text(exercise.exerciseName)
                    }
                }
            }
            // Stars fall behind the cards: rows are opaque, so only the header and the gutters show them and
            // every row stays fully readable. The grouped background moves from the list to this layer.
            .scrollContentBackground(.hidden)
            .background {
                ZStack {
                    Color(.systemGroupedBackground)
                    StarCelebration(hasRecord: summary.prCount > 0, seed: UInt64(max(0, summary.workoutNumber)))
                }
                .ignoresSafeArea()
            }
            .navigationDestination(for: ExerciseRecordsRoute.self) { route in
                ExerciseDetailView(exerciseID: route.exerciseID, initialSegment: .records)
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
        .sensoryFeedback(trigger: celebrated) { _, _ in
            summary.prCount > 0 ? .levelChange : .success
        }
        .onAppear { celebrated = true }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(Color.ok)
                .accessibilityHidden(true)
            Text("Workout complete")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if summary.workoutNumber >= 1 {
                Text("Your \(OrdinalFormat.string(summary.workoutNumber)) workout")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// One stat row: a white metric, or `tint` for the PR count.
    private func stat(_ title: String, _ value: String, spoken: String, tint: Color = .primary) -> some View {
        LabeledContent {
            MetricText(value, style: .title2)
                .foregroundStyle(tint)
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(spoken)")
    }

    /// A record row; it opens the exercise's Records segment when the exercise is known to the store.
    @ViewBuilder
    private func recordRow(_ record: PersonalRecord, exerciseID: UUID) -> some View {
        let text = Self.recordText(record, unit: summary.volumeUnit)
        let label = Label {
            Text(text)
        } icon: {
            Image(systemName: "trophy.fill")
                .foregroundStyle(Color.record)
        }
        if store?.exercise(id: exerciseID) != nil {
            NavigationLink(value: ExerciseRecordsRoute(exerciseID: exerciseID)) { label }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Personal record, \(text). Opens records")
                .accessibilityIdentifier("summary.pr.\(exerciseID.uuidString)")
        } else {
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Personal record, \(text)")
        }
    }

    // MARK: Text

    /// `1h 12min`, `45min`, `<1min`: the same text History shows.
    static func durationText(_ duration: TimeInterval) -> String {
        HistoryList.durationText(seconds: Int(duration))
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
        let weight = WeightFormat.text(record.weight, unit: unit)
        switch record.kind {
        case .e1rm: return "Estimated 1RM \(WeightFormat.text(record.value, unit: unit))"
        case .heaviest: return "Heaviest \(weight)"
        case .bestVolumeSet: return "Best set \(HistoryList.volumeText(record.value, unit: unit))"
        case .longestDuration: return "Longest \(ClockFormat.clock(seconds: Int(record.value)))"
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
