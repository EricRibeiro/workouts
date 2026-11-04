//
//  ActiveWorkoutCover.swift
//  Workouts
//

import SwiftUI
import UIKit
import WorkoutsKit

/// The logging screen (task 2.4): the in-progress workout's set table under a title with the start date and live elapsed
/// time, Minimise and Add Exercise in the toolbar. the rest ring is `RestRingItem` (2.5); Finish and Discard arrive with 2.8; the
/// regular-width secondary panes are placeholders until 2.10.
///
/// Reads the engine and the exercise store from the environment. Keeps the screen awake while open when Settings asks.
struct ActiveWorkoutCover: View {
    let minimise: () -> Void
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    @Environment(ExerciseStore.self) private var store: ExerciseStore?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isPickerPresented = false
    @State private var minimiseCount = 0

    var body: some View {
        NavigationStack {
            Group {
                if let engine, let store, let workout = engine.workout {
                    content(engine: engine, store: store, workout: workout)
                } else {
                    ContentUnavailableView(
                        "No workout in progress",
                        systemImage: "figure.strengthtraining.traditional"
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Minimise", systemImage: "chevron.down") {
                        minimiseCount += 1
                        minimise()
                    }
                    .accessibilityLabel("Minimise")
                    .accessibilityIdentifier("cover.minimise")
                }
                if engine?.workout != nil {
                    ToolbarItem(placement: .primaryAction) {
                        RestRingItem()
                    }
                    if let engine, engine.restTimer.isActive {
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button("Skip", systemImage: "forward.end") { try? engine.skipRest() }
                                .accessibilityLabel("Skip rest")
                                .accessibilityIdentifier("rest.toolbar.skip")
                            Button("+30 s", systemImage: "goforward.30") { try? engine.adjustRest(by: 30) }
                                .accessibilityLabel("Add 30 seconds")
                                .accessibilityIdentifier("rest.toolbar.plus30")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add Exercise", systemImage: "plus") { isPickerPresented = true }
                            .accessibilityLabel("Add Exercise")
                            .accessibilityIdentifier("cover.addExercise")
                    }
                }
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            ExercisePickerView(
                title: "Add Exercises",
                mode: .multiple(
                    add: { addExercises($0) },
                    superset: { addSuperset($0) }
                )
            )
            .presentationPlacement(.center)
        }
        // UIKit: SwiftUI has no idle-timer API.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = SettingsStore().keepScreenOn }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sensoryFeedback(.selection, trigger: minimiseCount)
        .accessibilityIdentifier("screen.activeWorkout")
    }

    @ViewBuilder
    private func content(engine: ActiveWorkoutEngine, store: ExerciseStore, workout: Workout) -> some View {
        let table = SetTable(source: EngineSetTableSource(engine: engine, store: store))
        Group {
            if horizontalSizeClass == .regular {
                ArrangementView {
                    table
                } secondary: {
                    VStack(spacing: 12) {
                        pane("Exercise", color: .green)
                        pane("Rest", color: .orange)
                    }
                    .padding()
                }
            } else {
                table
            }
        }
        .navigationTitle(workout.name)
        // The subtitle ticks every second from a background view, so the set table is not re-evaluated with it.
        .background {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Color.clear
                    .navigationSubtitle(subtitle(for: workout, at: context.date))
            }
        }
    }

    private func subtitle(for workout: Workout, at date: Date) -> String {
        let started = workout.startedAt.formatted(.dateTime.month(.abbreviated).day())
        let elapsed = ElapsedFormat.string(seconds: Int(date.timeIntervalSince(workout.startedAt)))
        return "\(started) · \(elapsed)"
    }

    private func addExercises(_ infos: [ExerciseInfo]) {
        _ = try? engine?.addExercises(infos)
    }

    /// The picker's Superset: adds the picks, then groups them as one superset.
    private func addSuperset(_ infos: [ExerciseInfo]) {
        guard let engine, let rows = try? engine.addExercises(infos) else { return }
        try? engine.makeSuperset(rows)
    }

    private func pane(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.title2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.opacity(0.2), in: .rect(cornerRadius: 16))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title) pane")
            .accessibilityIdentifier("cover.pane.\(title.lowercased())")
    }
}

#Preview {
    ActiveWorkoutCover(minimise: {})
}
