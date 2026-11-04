//
//  ActiveWorkoutCover.swift
//  Workouts
//

import SwiftUI
import UIKit
import WorkoutsKit

/// The logging screen (task 2.4): the in-progress workout's set table under a title with the start date and live elapsed
/// time, Minimise, Finish and Add Exercise in the toolbar. The rest ring is `RestRingItem` (2.5); the Finish dialogs are `FinishFlow`; the
/// regular-width secondary pane is `ExercisePane` (2.10).
///
/// Reads the engine and the exercise store from the environment. Keeps the screen awake while open when Settings asks.
struct ActiveWorkoutCover: View {
    let minimise: () -> Void
    /// Called after Finish saved the workout, with the numbers for the summary sheet (2.9).
    let onFinished: (FinishSummary) -> Void
    /// Called after the workout was discarded.
    let onDiscarded: () -> Void
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    @Environment(ExerciseStore.self) private var store: ExerciseStore?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isPickerPresented = false
    @State private var minimiseCount = 0
    @State private var finishFlow = FinishFlowState()
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var renameError: String?
    @State private var focusedSectionID: UUID?

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
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Finish", systemImage: "checkmark") {
                            guard let engine else { return }
                            finishFlow.begin(engine: engine, onFinished: onFinished, onDiscarded: onDiscarded)
                        }
                        .accessibilityLabel("Finish")
                        .accessibilityIdentifier("cover.finish")
                        // On the button so a popover (regular width) points at it.
                        .finishFlow(finishFlow)
                    }
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
        let sections = EngineSetTableSource(engine: engine, store: store).sections
        let focused = focusedSection(in: sections)
        // One ArrangementView in both widths, so folding never swaps the table's identity (draft, focus and scroll stay);
        // the pane is simply absent on compact width.
        ArrangementView {
            SetTable(
                source: EngineSetTableSource(engine: engine, store: store),
                focusedSection: $focusedSectionID
            )
        } secondary: {
            if horizontalSizeClass == .regular {
                ExercisePane(exerciseName: focused?.name)
            }
        }
        .arrangementViewStyle(
            .split.axes(horizontalSizeClass == .regular ? Axis.Set([.horizontal, .vertical]) : Axis.Set())
        )
        .navigationTitle(workout.name)
        .toolbarTitleMenu {
            Button("Rename…", systemImage: "pencil") {
                renameText = workout.name
                isRenaming = true
            }
            .accessibilityIdentifier("cover.titleMenu.rename")
            Button("Discard Workout", systemImage: "trash", role: .destructive) {
                finishFlow.requestDiscard(engine: engine, onDiscarded: onDiscarded)
            }
            .accessibilityIdentifier("cover.titleMenu.discard")
        }
        .alert("Rename Workout", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
                .accessibilityIdentifier("rename.field")
            Button("Save") { rename(engine, to: renameText) }
                .accessibilityIdentifier("rename.save")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("rename.cancel")
        }
        .alert(
            "Could Not Rename",
            isPresented: Binding(get: { renameError != nil }, set: { if !$0 { renameError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(renameError ?? "")
        }
        // The subtitle ticks every second from a background view, so the set table is not re-evaluated with it.
        .background {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Color.clear
                    .navigationSubtitle(subtitle(for: workout, at: context.date))
            }
        }
    }

    /// The block the exercise pane shows: the last focused or tapped one while it still exists, else the first with an
    /// unchecked set (`SetTableLayout.defaultFocusedSection`).
    private func focusedSection(in sections: [SetTableSection]) -> SetTableSection? {
        let id =
            sections.first(where: { $0.id == focusedSectionID })?.id
            ?? SetTableLayout.defaultFocusedSection(
                sections: sections.map { (id: $0.id, setChecks: $0.rows.map(\.isChecked)) }
            )
        return sections.first { $0.id == id }
    }

    private func subtitle(for workout: Workout, at date: Date) -> String {
        let started = workout.startedAt.formatted(.dateTime.month(.abbreviated).day())
        let elapsed = ElapsedFormat.string(seconds: Int(date.timeIntervalSince(workout.startedAt)))
        return "\(started) · \(elapsed)"
    }

    /// Saves a new name; blank or whitespace-only input is ignored, anything else is trimmed.
    private func rename(_ engine: ActiveWorkoutEngine, to text: String) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try engine.rename(to: name)
        } catch {
            renameError = "The name was not changed: \(error.localizedDescription)"
        }
    }

    private func addExercises(_ infos: [ExerciseInfo]) {
        _ = try? engine?.addExercises(infos)
    }

    /// The picker's Superset: adds the picks, then groups them as one superset.
    private func addSuperset(_ infos: [ExerciseInfo]) {
        guard let engine, let rows = try? engine.addExercises(infos) else { return }
        try? engine.makeSuperset(rows)
    }
}

#Preview {
    ActiveWorkoutCover(minimise: {}, onFinished: { _ in }, onDiscarded: {})
}
