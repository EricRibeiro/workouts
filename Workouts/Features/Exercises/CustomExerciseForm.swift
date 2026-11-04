//
//  CustomExerciseForm.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The custom exercise form (task 4.4): a `Form` sheet that creates a custom exercise or, with `editing`, changes one. Edit
/// mode adds **Archive** (history references the exercise) or **Delete** (nothing does), each behind a confirmation. The
/// rules live in the kit's `CustomExerciseForm`; this view only collects a draft and calls them.
struct CustomExerciseFormView: View {
    /// The custom exercise to edit; nil creates a new one.
    var editing: UUID?
    /// Starts the name (the picker passes its search text).
    var prefill = ""
    /// Called with the saved exercise just before the sheet closes.
    var onSaved: (ExerciseInfo) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ExerciseStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @State private var draft = CustomExerciseForm.Draft()
    @State private var loaded = false
    @State private var nameTouched = false
    @State private var removal: Removal?
    @State private var failure: String?
    @FocusState private var nameFocused: Bool

    private enum Removal: Identifiable {
        case archive, delete
        var id: Self { self }
    }

    private var isEditing: Bool { editing != nil }

    var body: some View {
        let issues = CustomExerciseForm.validate(draft, editing: editing, in: store)
        let labels = store.catalog.labels
        NavigationStack {
            Form {
                nameSection(issues)
                Section {
                    Picker("Body part", selection: $draft.bodyPart) {
                        Text("None").tag("")
                        ForEach(labels.bodyParts.keys.sorted { label($0, labels) < label($1, labels) }, id: \.self) {
                            Text(label($0, labels)).tag($0)
                        }
                    }
                    .accessibilityIdentifier("customExercise.bodyPart")
                    Picker("Weight type", selection: $draft.weightType) {
                        ForEach(Self.weightTypes, id: \.self) { Text(Self.weightTypeTitle($0)).tag($0) }
                    }
                    .accessibilityIdentifier("customExercise.weightType")
                }
                equipmentSection(labels)
                Section("Notes and instructions") {
                    TextField("One step per line", text: $draft.instructions, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityLabel("Notes and instructions")
                        .accessibilityIdentifier("customExercise.instructions")
                }
                defaultsSection(issues)
                if let editing { removalSection(for: editing) }
            }
            .navigationTitle(isEditing ? "Edit Exercise" : "New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("customExercise.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { save() }
                        .disabled(!issues.isEmpty)
                        .accessibilityLabel("Save")
                        .accessibilityIdentifier("customExercise.save")
                }
            }
            .confirmationDialog(
                removal == .delete ? "Delete this exercise?" : "Archive this exercise?",
                isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
                titleVisibility: .visible,
                presenting: removal
            ) { kind in
                switch kind {
                case .archive:
                    Button("Archive", role: .destructive) { remove(.archive) }
                case .delete:
                    Button("Delete", role: .destructive) { remove(.delete) }
                }
            } message: { kind in
                switch kind {
                case .archive:
                    Text("It is hidden from the list and the picker, but stays in your history. Show Retired lists it.")
                case .delete:
                    Text("Nothing uses it, so it is removed for good.")
                }
            }
            .alert(
                "Could Not Save",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
            .task { load() }
        }
        .accessibilityIdentifier(isEditing ? "screen.editExercise" : "screen.newExercise")
    }

    // MARK: Sections

    private func nameSection(_ issues: [CustomExerciseForm.Issue]) -> some View {
        Section {
            TextField("Exercise name", text: $draft.name)
                .focused($nameFocused)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .accessibilityLabel("Name")
                .accessibilityIdentifier("customExercise.name")
                .onChange(of: draft.name) { nameTouched = true }
        } header: {
            Text("Name")
        } footer: {
            // "Give the exercise a name." waits for the first keystroke; a taken or too-long name shows at once.
            if let issue = issues.first(where: {
                $0 == .nameTaken || $0 == .nameTooLong || ($0 == .nameMissing && nameTouched)
            }) {
                Text(issue.message)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("customExercise.nameError")
            }
        }
    }

    private func equipmentSection(_ labels: LibraryLabels) -> some View {
        Section("Equipment") {
            ForEach(
                labels.equipment.keys.sorted {
                    label($0, labels, equipment: true) < label($1, labels, equipment: true)
                },
                id: \.self
            ) { key in
                let isOn = draft.equipment.contains(key)
                Button {
                    if let index = draft.equipment.firstIndex(of: key) {
                        draft.equipment.remove(at: index)
                    } else {
                        draft.equipment.append(key)
                    }
                } label: {
                    HStack {
                        Text(label(key, labels, equipment: true))
                            .foregroundStyle(.primary)
                        Spacer()
                        if isOn {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(key, labels, equipment: true))
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("customExercise.equipment.\(key)")
            }
        }
    }

    private func defaultsSection(_ issues: [CustomExerciseForm.Issue]) -> some View {
        let unitName = (draft.unit ?? settings.defaultUnit).rawValue
        return Section {
            Picker("Weight unit", selection: $draft.unit) {
                Text("Default (\(settings.defaultUnit.rawValue))").tag(WeightUnit?.none)
                ForEach(WeightUnit.allCases, id: \.self) { Text($0.rawValue).tag(WeightUnit?.some($0)) }
            }
            .accessibilityIdentifier("customExercise.unit")
            Picker("Bar", selection: $draft.barType) {
                Text("No bar").tag(BarType.none)
                Text("Olympic bar (45 lb / 20 kg)").tag(BarType.olympic)
                Text("EZ bar").tag(BarType.ez)
                Text("Custom weight").tag(BarType.custom)
            }
            .accessibilityIdentifier("customExercise.bar")
            if draft.barType == .custom {
                LabeledContent("Bar weight (\(unitName))") {
                    TextField("0", text: $draft.barWeightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Bar weight")
                        .accessibilityIdentifier("customExercise.barWeight")
                }
            }
            LabeledContent("Rest timer (seconds)") {
                TextField("Default", text: $draft.restText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Rest timer in seconds")
                    .accessibilityIdentifier("customExercise.rest")
            }
        } header: {
            Text("Defaults for new sets")
        } footer: {
            if let issue = issues.first(where: { $0 == .restInvalid || $0 == .barWeightInvalid }) {
                Text(issue.message)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("customExercise.defaultsError")
            }
        }
    }

    @ViewBuilder
    private func removalSection(for id: UUID) -> some View {
        Section {
            if CustomExerciseForm.isReferenced(exerciseID: id, in: modelContext) {
                Button("Archive Exercise", systemImage: "archivebox", role: .destructive) { removal = .archive }
                    .accessibilityLabel("Archive Exercise")
                    .accessibilityIdentifier("customExercise.archive")
            } else {
                Button("Delete Exercise", systemImage: "trash", role: .destructive) { removal = .delete }
                    .accessibilityLabel("Delete Exercise")
                    .accessibilityIdentifier("customExercise.delete")
            }
        } footer: {
            Text("Exercises with history are archived instead of deleted.")
        }
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let editing {
            if let exercise = CustomExerciseForm.exercise(id: editing, in: modelContext) {
                draft = CustomExerciseForm.Draft(exercise)
            }
        } else {
            draft.name = prefill.trimmingCharacters(in: .whitespacesAndNewlines)
            nameTouched = !draft.name.isEmpty
            if draft.name.isEmpty { nameFocused = true }
        }
    }

    private func save() {
        do {
            let id: UUID
            if let editing, let exercise = CustomExerciseForm.exercise(id: editing, in: modelContext) {
                try CustomExerciseForm.update(exercise, from: draft, in: modelContext, store: store)
                id = exercise.id
            } else {
                id = try CustomExerciseForm.create(draft, in: modelContext, store: store).id
            }
            if let info = store.exercise(id: id) { onSaved(info) }
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func remove(_ kind: Removal) {
        guard let editing, let exercise = CustomExerciseForm.exercise(id: editing, in: modelContext) else { return }
        do {
            switch kind {
            case .archive: try CustomExerciseForm.archive(exercise, in: modelContext, store: store)
            case .delete: try CustomExerciseForm.delete(exercise, in: modelContext, store: store)
            }
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }

    // MARK: Labels

    private func label(_ key: String, _ labels: LibraryLabels, equipment: Bool = false) -> String {
        equipment
            ? ExerciseFilter.equipmentLabel(key, labels: labels)
            : ExerciseFilter.bodyPartLabel(key, labels: labels)
    }

    private static let weightTypes: [WeightType] = [
        .weighted, .barbell, .dumbbell, .machine, .bodyweight, .assisted, .band, .unweighted,
    ]

    static func weightTypeTitle(_ type: WeightType) -> String {
        switch type {
        case .weighted: "Weight and reps"
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .machine: "Machine"
        case .bodyweight: "Bodyweight"
        case .assisted: "Assisted bodyweight (less is better)"
        case .band: "Band"
        case .unweighted: "Reps or time only"
        }
    }
}

#if DEBUG
    /// The gallery host for Edit: the sample data's custom exercise (its history makes the form offer Archive).
    struct CustomExerciseFormEditDemo: View {
        @Query(filter: #Predicate<Exercise> { !$0.retired }) private var exercises: [Exercise]

        var body: some View {
            if let exercise = exercises.first {
                CustomExerciseFormView(editing: exercise.id)
            } else {
                ContentUnavailableView("No custom exercise", systemImage: "questionmark")
            }
        }
    }

    #Preview("New") {
        PreviewGallery.host("CustomExerciseForm")
    }

    #Preview("Edit") {
        PreviewGallery.host("CustomExerciseFormEdit")
    }
#endif
