//
//  PastWorkoutEditor.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The past-workout editor (task 5.6), pushed from the workout detail by `HistoryRoute.editWorkout`: the name (title
/// menu, Rename…), the start time and duration in minutes under the bar, and the SetTable in past mode (values only, no
/// Previous, no check). Every edit goes to a `PastWorkoutDraft`; Save writes it to the workout in one go, Cancel drops it
/// (asking first when something changed). Regular width puts the table beside, above or across the fold from the exercise
/// pane with an `ArrangementView`, as the logging screen does.
struct PastWorkoutEditor: View {
    let workoutID: UUID

    @Query(filter: #Predicate<Workout> { $0.finishedAt != nil }) private var finished: [Workout]

    var body: some View {
        if let workout = finished.first(where: { $0.id == workoutID }) {
            Editor(workout: workout)
        } else {
            ContentUnavailableView(
                "Workout Not Found",
                systemImage: "questionmark.folder",
                description: Text("That workout does not exist.")
            )
            .accessibilityIdentifier("history.detail.missing")
        }
    }
}

/// The editor proper, made once the workout is resolved so the draft is created exactly once per presentation.
private struct Editor: View {
    let workout: Workout

    @Environment(ExerciseStore.self) private var store
    @Environment(SaveErrors.self) private var errors: SaveErrors?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var draft: PastWorkoutDraft
    /// The draft as it was when the editor opened; dirty means different from this.
    @State private var original: PastWorkoutDraft
    @State private var isDiscardConfirming = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var focusedSectionID: UUID?
    @FocusState private var isDurationFocused: Bool

    init(workout: Workout) {
        self.workout = workout
        let initial = PastWorkoutDraft(workout)
        _draft = State(initialValue: initial)
        _original = State(initialValue: initial)
    }

    private var isDirty: Bool { draft.hasChanges(from: original) }

    var body: some View {
        let source = PastSetTableSource(draft: $draft, store: store)
        let sections = source.sections
        VStack(spacing: 0) {
            details
            Divider()
            arrangement(source: source, sections: sections)
        }
        .navigationTitle(draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbarTitleMenu {
            Button("Rename…", systemImage: "pencil") {
                renameText = draft.name
                isRenaming = true
            }
            .accessibilityIdentifier("pastEditor.titleMenu.rename")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark", action: cancel)
                    .accessibilityLabel("Cancel")
                    .accessibilityIdentifier("pastEditor.cancel")
                    // On the button so the regular-width popover points at it.
                    .confirmationDialog(
                        "Discard changes?",
                        isPresented: $isDiscardConfirming,
                        titleVisibility: .visible
                    ) {
                        Button("Discard Changes", role: .destructive) { dismiss() }
                            .accessibilityIdentifier("pastEditor.discard")
                        Button("Keep Editing", role: .cancel) {}
                            .accessibilityIdentifier("pastEditor.keepEditing")
                    } message: {
                        Text("Your edits to this workout will be lost.")
                    }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark", action: save)
                    .accessibilityLabel("Save")
                    .accessibilityIdentifier("pastEditor.save")
                    .disabled(!isDirty)
            }
        }
        .alert("Rename Workout", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
                .accessibilityIdentifier("pastEditor.rename.field")
            Button("Save") { draft.rename(to: renameText) }
                .accessibilityIdentifier("pastEditor.rename.save")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("pastEditor.rename.cancel")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.pastEditor")
    }

    // MARK: Start and duration

    /// Start time and duration under the bar; stacks when the text is large.
    private var details: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                startPicker
                Spacer(minLength: 0)
                durationControl
            }
            VStack(alignment: .leading, spacing: 8) {
                startPicker
                durationControl
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var startPicker: some View {
        DatePicker(
            "Start",
            selection: $draft.startedAt,
            in: ...Date.now,
            displayedComponents: [.date, .hourAndMinute]
        )
        .fixedSize()
        .accessibilityIdentifier("pastEditor.start")
    }

    /// Minutes as a number field with a stepper beside it: typing handles the long jumps, the stepper the small ones.
    private var durationControl: some View {
        let minutes = Binding(
            get: { draft.durationMinutes },
            set: { draft.setDurationMinutes($0) }
        )
        return HStack(spacing: 8) {
            Text("Duration")
            TextField("Minutes", value: minutes, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .focused($isDurationFocused)
                .toolbar {
                    // The number pad has no Return; shown only while this field has focus so the set keyboard's
                    // group is left alone.
                    if isDurationFocused {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done", systemImage: "keyboard.chevron.compact.down") { isDurationFocused = false }
                                .accessibilityLabel("Done")
                                .accessibilityIdentifier("pastEditor.duration.done")
                        }
                    }
                }
                .accessibilityLabel("Duration in minutes")
                .accessibilityIdentifier("pastEditor.duration")
            Text("min")
                .foregroundStyle(.secondary)
            Stepper("Duration", value: minutes, in: 0...PastWorkoutDraft.maxDurationMinutes)
                .labelsHidden()
                .accessibilityLabel("Duration")
                .accessibilityValue("\(draft.durationMinutes) minutes")
                .accessibilityIdentifier("pastEditor.duration.stepper")
        }
        .fixedSize()
    }

    // MARK: Table

    /// One ArrangementView in both widths so folding never swaps the table's identity (draft, focus and scroll stay); the
    /// pane is simply absent, and the split disabled, on compact width (as in the logging screen).
    private func arrangement(source: any SetTableDataSource, sections: [SetTableSection]) -> some View {
        ArrangementView {
            SetTable(source: source, focusedSection: $focusedSectionID)
        } secondary: {
            if horizontalSizeClass == .regular {
                let focused = focusedSection(in: sections)
                ExercisePane(exerciseName: focused?.name, exerciseID: focused?.exerciseID)
            }
        }
        .arrangementViewStyle(
            .split.axes(horizontalSizeClass == .regular ? Axis.Set([.horizontal, .vertical]) : Axis.Set())
        )
    }

    /// The block the pane shows: the last focused one while it still exists, else the first.
    private func focusedSection(in sections: [SetTableSection]) -> SetTableSection? {
        sections.first { $0.id == focusedSectionID } ?? sections.first
    }

    // MARK: Actions

    private func cancel() {
        if isDirty {
            isDiscardConfirming = true
        } else {
            dismiss()
        }
    }

    private func save() {
        do {
            try draft.save(to: workout, in: context)
            dismiss()
        } catch {
            // The draft stays as it is, so Save can be tried again.
            errors?.report(error)
        }
    }
}

// MARK: - Gallery and previews

#if DEBUG
    /// The editor of the newest sample workout, for the gallery (`-preview PastEditor`) and the previews.
    struct PastEditorDemo: View {
        @Query(
            filter: #Predicate<Workout> { $0.finishedAt != nil },
            sort: \Workout.startedAt,
            order: .reverse
        ) private var finished: [Workout]
        @State private var settings = SettingsStore()
        @State private var errors = SaveErrors()

        var body: some View {
            NavigationStack {
                if let first = finished.first {
                    PastWorkoutEditor(workoutID: first.id)
                } else {
                    ProgressView()
                }
            }
            .environment(settings)
            .environment(errors)
            .saveErrorAlert()
        }
    }

    #Preview("Large") {
        PreviewGallery.host("PastEditor")
            .dynamicTypeSize(.large)
    }

    #Preview("Accessibility 3") {
        PreviewGallery.host("PastEditor")
            .dynamicTypeSize(.accessibility3)
    }
#endif
