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
    @Environment(SaveErrors.self) private var errors: SaveErrors?
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isPickerPresented = false
    @State private var minimiseCount = 0
    @State private var finishFlow = FinishFlowState()
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var renameError: String?
    @State private var focusedSectionID: UUID?
    /// The exercise whose detail the compact-width sheet shows (regular width has the pane instead).
    @State private var infoExercise: UUID?
    /// The block menu's pending prompts (task 3.6d).
    @State private var blockSheets = BlockActionState()
    /// The last content shown for a running workout, as plain values (never the model, which Finish and Discard delete),
    /// so the cover keeps drawing it while it animates away instead of flashing the empty state.
    @State private var lastShown: LastShown?
    /// A set cell has keyboard focus (`SetTableEditingKey`): the number pad leaves the closed display's trailing strip about
    /// three items tall, so only Minimise and Finish stay; the rest timer lives in the keyboard accessory meanwhile.
    @State private var isEditingSet = false
    /// Set 1.5 s after a scroll ends: the system's own title minimisation (`.automatic` hides the header while the table is
    /// scrolled down) is switched to `.never`, which brings the header back with the system's animation; the next scroll
    /// switches it back so the header can hide again. There is no API to re-expand a minimised bar directly.
    @State private var isHeaderPinned = false
    /// Counts scroll endings; the `.task(id:)` below restarts (and so cancels the pending restore) whenever it changes.
    @State private var scrollEndCount = 0
    @State private var isHeaderRestorePending = false

    var body: some View {
        NavigationStack {
            Group {
                if let engine, let store, let workout = engine.workout {
                    content(engine: engine, store: store, workout: workout)
                } else if let lastShown {
                    dismissing(lastShown)
                } else {
                    ContentUnavailableView(
                        "No workout in progress",
                        systemImage: "figure.strengthtraining.traditional"
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarMinimizationBehavior(isHeaderPinned ? .never : .automatic, for: .navigationBar)
            .onScrollPhaseChange { old, new in
                // A scroll starting cancels the pending restore and lets the header hide again; one ending (finger lifted,
                // or the fling settled) starts the timer.
                if new == .idle {
                    guard old == .decelerating || old == .interacting else { return }
                    isHeaderRestorePending = true
                    scrollEndCount += 1
                } else {
                    isHeaderRestorePending = false
                    scrollEndCount += 1
                    if isHeaderPinned { isHeaderPinned = false }
                }
            }
            .task(id: scrollEndCount) {
                guard isHeaderRestorePending else { return }
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
                withAnimation { isHeaderPinned = true }
            }
            .onPreferenceChange(SetTableEditingKey.self) { isEditingSet = $0 }
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
                    // With the number pad up the closed strip is short: Finish stays, Add Exercise folds first.
                    .visibilityPriority(.high)
                    if !isEditingSet {
                        ToolbarItem(placement: .primaryAction) {
                            RestRingItem()
                        }
                    }
                    if let engine, engine.restTimer.isActive, !isEditingSet {
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button("Skip", systemImage: "forward.end") { perform { try engine.skipRest() } }
                                .accessibilityLabel("Skip rest")
                                .accessibilityIdentifier("rest.toolbar.skip")
                            Button("+30 s", systemImage: "goforward.30") { perform { try engine.adjustRest(by: 30) } }
                                .accessibilityLabel("Add 30 seconds")
                                .accessibilityIdentifier("rest.toolbar.plus30")
                        }
                    }
                    if !isEditingSet {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Add Exercise", systemImage: "plus") { isPickerPresented = true }
                                .accessibilityLabel("Add Exercise")
                                .accessibilityIdentifier("cover.addExercise")
                        }
                        .visibilityPriority(.low)
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
        .exerciseInfoSheet(exerciseID: $infoExercise)
        // UIKit: SwiftUI has no idle-timer API. Driven by "the cover is up, a workout is running and Settings asks", so
        // Finish and Discard (workout gone) release the screen even before the cover has finished animating away.
        .onAppear { applyKeepScreenOn() }
        .onChange(of: settings?.keepScreenOn) { applyKeepScreenOn() }
        .onChange(of: engine?.workout != nil) { applyKeepScreenOn() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sensoryFeedback(.selection, trigger: minimiseCount)
        // The cover is a presentation of its own, so it hosts its own save-error alert.
        .saveErrorAlert()
        .accessibilityIdentifier("screen.activeWorkout")
    }

    private func applyKeepScreenOn() {
        let wanted = settings?.keepScreenOn ?? SettingsStore.keepScreenOnDefault
        UIApplication.shared.isIdleTimerDisabled = wanted && engine?.workout != nil
    }

    @ViewBuilder
    private func content(engine: ActiveWorkoutEngine, store: ExerciseStore, workout: Workout) -> some View {
        let source = EngineSetTableSource(engine: engine, store: store, errors: errors)
        let sections = source.sections
        arrangement(
            source: source,
            sections: sections,
            blockActions: blockSheets.actions(host: blockHost(engine: engine, workout: workout))
        )
        .blockActionSheets(blockSheets, host: blockHost(engine: engine, workout: workout))
        #if DEBUG
            .onAppear {
                // `-openExerciseInfo`: opens the first exercise's info sheet, for screenshots of its detents.
                if ProcessInfo.processInfo.arguments.contains("-openExerciseInfo"), infoExercise == nil,
                    let first = sections.first
                {
                    infoExercise = first.exerciseID
                }
            }
        #endif
        .navigationTitle(workout.name)
        .onChange(
            of: LastShown(name: workout.name, startedAt: workout.startedAt, sections: sections),
            initial: true
        ) {
            _,
            new in lastShown = new
        }
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
        .navigationSubtitle(subtitle(startedAt: workout.startedAt))
    }

    /// What the cover shows between Finish or Discard and the end of its dismissal: the last content, read-only.
    private func dismissing(_ last: LastShown) -> some View {
        arrangement(source: FrozenSetTableSource(sections: last.sections), sections: last.sections)
            .allowsHitTesting(false)
            .navigationTitle(last.name)
            .navigationSubtitle(subtitle(startedAt: last.startedAt))
    }

    /// One ArrangementView in both widths, so folding never swaps the table's identity (draft, focus and scroll stay);
    /// the pane is simply absent on compact width and while the workout has no exercise (nothing for it to show).
    private func arrangement(
        source: any SetTableDataSource,
        sections: [SetTableSection],
        blockActions: SetTableBlockActions? = nil
    ) -> some View {
        let showsPane = horizontalSizeClass == .regular && !sections.isEmpty
        return ArrangementView {
            SetTable(
                source: source,
                onSelectExercise: horizontalSizeClass == .compact
                    ? { infoExercise = $0.exerciseID } : nil,
                focusedSection: $focusedSectionID,
                blockActions: blockActions
            )
        } secondary: {
            if showsPane {
                let focused = focusedSection(in: sections)
                ExercisePane(exerciseName: focused?.name, exerciseID: focused?.exerciseID)
            }
        }
        // The system split's placement in every pose but the half-open laptop one, where the table drops to the lower half
        // (6.1); one view tree throughout, so no pose change recreates the table.
        .arrangementViewStyle(
            BenchArrangementStyle(
                axes: showsPane ? Axis.Set([.horizontal, .vertical]) : Axis.Set(),
                showsRestCountdown: true
            )
        )
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

    /// "Nov 4 · 12:34", the elapsed time counting up by itself (a `.timer` Text), so nothing re-evaluates each second.
    private func subtitle(startedAt: Date) -> Text {
        let started = startedAt.formatted(.dateTime.month(.abbreviated).day())
        return Text("\(started) · ") + Text(startedAt, style: .timer)
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

    /// Runs an engine call and reports a failure through the save-error alert.
    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errors?.report(error)
        }
    }

    /// The engine behind the block menu's prompts. Each closure resolves the row by the section id; a failure is reported
    /// through `perform` (the engine rolls back or keeps the value as its rules say).
    private func blockHost(engine: ActiveWorkoutEngine, workout: Workout) -> BlockActionHost {
        func row(_ id: UUID) -> WorkoutExercise? { (workout.exercises ?? []).first { $0.id == id } }
        return BlockActionHost(
            blocks: (workout.exercises ?? []).sorted { $0.position < $1.position }.map {
                BlockActionBlock(
                    id: $0.id,
                    exerciseID: $0.exerciseID,
                    name: $0.exerciseName,
                    note: $0.note,
                    restSeconds: $0.restSeconds,
                    supersetGroup: $0.supersetGroup,
                    unit: $0.unit,
                    barType: $0.barType,
                    barWeight: $0.barWeight
                )
            },
            idPrefix: "cover",
            removeMessage: "Its sets, checked or not, are removed from the workout.",
            setNote: { id, text in
                guard let row = row(id) else { return }
                perform { try engine.setNote(text, for: row) }
            },
            addWarmups: { id in
                guard let row = row(id) else { return true }
                do {
                    return try engine.addWarmupSets(to: row)
                } catch {
                    errors?.report(error)
                    return true
                }
            },
            setRest: { id, seconds in
                guard let row = row(id) else { return }
                perform { try engine.setRest(seconds, for: row) }
            },
            remove: { id in
                guard let row = row(id) else { return }
                perform { try engine.removeExercise(row) }
            },
            replace: { id, info in
                guard let row = row(id) else { return }
                perform { try engine.replaceExercise(row, with: info) }
            },
            makeSuperset: { id, picked in
                perform { try engine.makeSuperset(([id] + picked).compactMap(row)) }
            },
            removeFromSuperset: { id in
                guard let row = row(id) else { return }
                perform { try engine.removeFromSuperset(row) }
            },
            savePreferences: { id, values in
                guard let row = row(id) else { return }
                perform {
                    try engine.setUnit(values.unit, for: row)
                    try engine.setBar(values.barType, weight: values.barWeight, for: row)
                }
            }
        )
    }

    private func addExercises(_ infos: [ExerciseInfo]) {
        perform { _ = try engine?.addExercises(infos) }
    }

    /// The picker's Superset: adds the picks, then groups them as one superset.
    private func addSuperset(_ infos: [ExerciseInfo]) {
        guard let engine else { return }
        perform { try engine.makeSuperset(try engine.addExercises(infos)) }
    }
}

#Preview {
    ActiveWorkoutCover(minimise: {}, onFinished: { _ in }, onDiscarded: {})
}

/// Plain values of the running workout's logging screen, kept after the model is gone.
private struct LastShown: Equatable {
    let name: String
    let startedAt: Date
    let sections: [SetTableSection]
}

/// A read-only table over cached sections: the cover's last frame while Finish or Discard dismisses it.
private struct FrozenSetTableSource: SetTableDataSource {
    let sections: [SetTableSection]
    var mode: SetTableMode { .active }
    func cycleKind(of setID: UUID) {}
    func applyPrevious(to setID: UUID) {}
    func commitWeight(_ weight: Double?, for setID: UUID) {}
    func commitReps(_ value: Int?, for setID: UUID) {}
    func toggleCheck(of setID: UUID) -> Bool { false }
    func addSet(to sectionID: UUID) {}
    func deleteSet(_ setID: UUID) {}
    func reorder(_ order: [UUID]) {}
}
