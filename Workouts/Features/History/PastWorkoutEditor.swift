//
//  PastWorkoutEditor.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The past-workout editor (task 5.6), presented as a full-screen cover (modal: a self-contained edit with Save and Cancel, so a tab reselect cannot pop it and lose
/// the edits) from the workout detail or a History row, in a `NavigationStack` of its own: the name (title
/// menu, Rename…), the start time and duration in minutes under the bar, and the SetTable in past mode (values only, no
/// Previous, no check). Every edit goes to a `PastWorkoutDraft`; Save writes it to the workout in one go, Cancel drops it
/// (asking first when something changed). Regular width puts the table beside, above or across the fold from the exercise
/// pane with an `ArrangementView`, as the logging screen does.
struct PastWorkoutEditor: View {
    let workoutID: UUID

    /// This workout alone (zero or one row), not every finished workout.
    @Query private var found: [Workout]
    @Environment(ExerciseStore.self) private var store

    init(workoutID: UUID) {
        self.workoutID = workoutID
        _found = Query(Workout.finished(id: workoutID))
    }

    var body: some View {
        if let workout = found.first {
            Editor(workout: workout, timedByDefault: { [store] in store.exercise(id: $0)?.isTimed ?? false })
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var draft: PastWorkoutDraft
    /// The draft as it was when the editor opened; dirty means different from this.
    @State private var original: PastWorkoutDraft
    @State private var isDiscardConfirming = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var focusedSectionID: UUID?
    @State private var blockSheets = BlockActionState()
    @FocusState private var isDurationFocused: Bool

    init(workout: Workout, timedByDefault: @escaping (UUID) -> Bool) {
        self.workout = workout
        let initial = PastWorkoutDraft(workout, timedByDefault: timedByDefault)
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
        .blockActionSheets(blockSheets, host: blockHost)
        .alert("Rename Workout", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
                .accessibilityIdentifier("pastEditor.rename.field")
            Button("Save") { draft.rename(to: renameText) }
                .accessibilityIdentifier("pastEditor.rename.save")
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("pastEditor.rename.cancel")
        }
        // Fires when "Discard changes?" is raised, not when Discard is tapped: confirming dismisses this screen in the
        // same pass, which would cut the haptic off, and the presenters (several) cannot be hooked cheaply.
        .sensoryFeedback(.warning, trigger: isDiscardConfirming) { _, shown in shown }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.pastEditor")
    }

    // MARK: Start and duration

    /// Start time and duration under the bar; stacks when the text is large. At accessibility sizes nothing keeps its
    /// ideal width (a fixed-size row wider than the screen is centred by its parent and clipped on both edges): the
    /// controls take the proposed width and the duration label sits above its field.
    @ViewBuilder
    private var details: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    startPicker
                    durationControl
                }
            } else {
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var startPicker: some View {
        let picker = DatePicker(
            "Start",
            selection: $draft.startedAt,
            in: ...Date.now,
            displayedComponents: [.date, .hourAndMinute]
        )
        if dynamicTypeSize.isAccessibilitySize {
            // The label would share a row with the date pill and be squeezed to "S…": stack it above instead.
            VStack(alignment: .leading, spacing: 8) {
                Text("Start").accessibilityHidden(true)
                picker.labelsHidden().accessibilityIdentifier("pastEditor.start")
            }
        } else {
            picker.fixedSize().accessibilityIdentifier("pastEditor.start")
        }
    }

    /// Minutes as a number field with a stepper beside it: typing handles the long jumps, the stepper the small ones.
    /// At accessibility sizes the label stacks above the field, which grows to fill the row.
    private var durationControl: some View {
        let minutes = Binding(
            get: { draft.durationMinutes },
            set: { draft.setDurationMinutes($0) }
        )
        let isLarge = dynamicTypeSize.isAccessibilitySize
        let layout =
            isLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        let field = HStack(spacing: 8) {
            TextField("Minutes", value: minutes, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minWidth: 72, maxWidth: isLarge ? .infinity : 72)
                // A grey fill (accent while typing), matching the date pills and the stepper beside it.
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            isDurationFocused
                                ? AnyShapeStyle(Color.accentColor.opacity(0.2))
                                : AnyShapeStyle(Color(.quaternarySystemFill))
                        )
                )
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
                .fixedSize()
                .accessibilityLabel("Duration")
                .accessibilityValue("\(draft.durationMinutes) \(draft.durationMinutes == 1 ? "minute" : "minutes")")
                .accessibilityIdentifier("pastEditor.duration.stepper")
        }
        return layout {
            Text("Duration")
            if isLarge { field } else { field.fixedSize() }
        }
    }

    // MARK: Block menu

    /// The draft behind the block menu's one prompt. Note… edits the draft (written on Save, dropped on Cancel). The other
    /// entries are not offered, so their closures are inert.
    private var blockHost: BlockActionHost {
        BlockActionHost(
            blocks: draft.exercises.map {
                BlockActionBlock(
                    id: $0.id,
                    exerciseID: $0.exerciseID,
                    name: $0.name,
                    note: $0.note,
                    restSeconds: nil,
                    supersetGroup: $0.supersetGroup,
                    unit: $0.unit,
                    barType: .olympic,
                    barWeight: nil
                )
            },
            idPrefix: "pastEditor",
            removeMessage: "",
            setNote: { draft.setNote($1, for: $0) },
            addWarmups: { _ in true },
            setRest: { _, _ in },
            remove: { _ in },
            replace: { _, _ in },
            makeSuperset: { _, _ in },
            removeFromSuperset: { _ in },
            savePreferences: { _, _ in }
        )
    }

    // MARK: Table

    /// One ArrangementView in both widths so folding never swaps the table's identity (draft, focus and scroll stay); the
    /// pane is simply absent, and the split disabled, on compact width (as in the logging screen) and while the workout has
    /// no exercise (nothing for the pane to show).
    private func arrangement(source: any SetTableDataSource, sections: [SetTableSection]) -> some View {
        let showsPane = horizontalSizeClass == .regular && !sections.isEmpty
        return ArrangementView {
            SetTable(source: source, focusedSection: $focusedSectionID, blockActions: blockSheets.noteActions())
        } secondary: {
            if showsPane {
                let focused = focusedSection(in: sections)
                ExercisePane(exerciseName: focused?.name, exerciseID: focused?.exerciseID)
            }
        }
        // The system split's placement in every pose but the half-open laptop one, where the table drops to the lower half
        // (6.1); one view tree throughout, so no pose change recreates the table.
        .arrangementViewStyle(
            BenchArrangementStyle(axes: showsPane ? Axis.Set([.horizontal, .vertical]) : Axis.Set())
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

// MARK: - Presenting

/// A past workout to edit, for `fullScreenCover(item:)`.
struct PastEditorTarget: Identifiable, Hashable {
    let id: UUID
}

extension View {
    /// Presents the past-workout editor for `target` as a full-screen cover with its own `NavigationStack`.
    func pastWorkoutEditorCover(_ target: Binding<PastEditorTarget?>) -> some View {
        fullScreenCover(item: target) { item in
            NavigationStack {
                PastWorkoutEditor(workoutID: item.id)
            }
            .editorCoverHost()
        }
    }
}

// MARK: - Gallery and previews

#if DEBUG
    /// The editor of the newest sample workout, for the gallery (`-preview PastEditor`) and the previews.
    struct PastEditorDemo: View {
        @Query(
            filter: Workout.finishedPredicate,
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
