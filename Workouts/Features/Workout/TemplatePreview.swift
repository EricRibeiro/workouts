//
//  TemplatePreview.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The preview of a template (task 3.3, `workout.md` sections 3 and 5): its name, folder and last performance, a prominent
/// **Start Workout** directly under them, then the exercise rows (`N × Name`, body part, planned sets, a superset bar and
/// an `info.circle` that opens the exercise's detail). Nothing is bottom-anchored.
///
/// Shown as a medium-detent sheet at compact width (``TemplatePreviewSheet``) and pushed with a zoom at regular width.
/// `started` runs once a workout is behind the cover; the caller dismisses the preview and presents the cover. `edit` runs
/// from the **Edit** item; the caller closes the preview if it is a sheet and pushes the editor (task 3.4).
struct TemplatePreview: View {
    let template: Template
    let started: () -> Void
    let edit: (Template) -> Void

    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    @Environment(SaveErrors.self) private var errors: SaveErrors?
    @Environment(ExerciseStore.self) private var store: ExerciseStore?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var context
    @Environment(StoreGeneration.self) private var generation: StoreGeneration?
    /// The newest edit among finished workouts: with the store generation it keys "last performed", which is read once
    /// per change in the task (one fetch) rather than from an observed query of every finished workout.
    @Query(Workout.newestFinishedEdit) private var newest: [Workout]
    @State private var lastPerformedIndex = TemplateCardSummary.LastPerformedIndex()
    @State private var flow = StartWorkoutFlow()
    /// The exercise whose detail the row's `info.circle` pushes. State plus an item destination rather than a value
    /// `NavigationLink`: at regular width this view is itself pushed by an item destination, and a value link inside it
    /// never activates (SwiftUI logs "declared earlier on the stack").
    @State private var aboutExerciseID: UUID?

    private var rows: [TemplatePreviewRow] { TemplatePreviewRow.rows(for: template) }

    var body: some View {
        let rows = rows
        let lastPerformed = TemplateCardSummary.make(for: template, index: lastPerformedIndex).lastPerformed
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(lastPerformed: lastPerformed)
                startButton(isEnabled: !rows.isEmpty)
                if rows.isEmpty {
                    Text("This template has no exercises yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("template.preview.empty")
                } else {
                    exerciseList(rows)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") { edit(template) }
                    .accessibilityLabel("Edit")
                    .accessibilityIdentifier("template.edit")
            }
        }
        .navigationDestination(item: $aboutExerciseID) { ExerciseDetailView(exerciseID: $0) }
        .task(id: FinishedWorkoutsStamp(newestEdit: newest.first?.updatedAt, generation: generation?.value ?? 0)) {
            let finished = (try? context.fetch(Workout.allFinished)) ?? []
            lastPerformedIndex = TemplateCardSummary.LastPerformedIndex(finishedWorkouts: finished)
        }
        .accessibilityIdentifier("template.preview")
    }

    // MARK: Header

    private func header(lastPerformed: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.name)
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("template.preview.title")
            if let folder = template.folder {
                Label(folder.name, systemImage: "folder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let lastPerformed {
                Label("Last performed · \(lastPerformed)", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("template.preview.lastPerformed")
            }
            if !template.note.isEmpty {
                Text(template.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func startButton(isEnabled: Bool) -> some View {
        Button {
            flow.begin(.template(template), engine: engine, errors: errors, present: started)
        } label: {
            Label("Start Workout", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(!isEnabled)
        .startWorkoutFlow(flow)
        .accessibilityIdentifier("template.start")
    }

    // MARK: Exercises

    private func exerciseList(_ rows: [TemplatePreviewRow]) -> some View {
        let hasSuperset = rows.contains { $0.supersetGroup != nil }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                exerciseRow(row, indented: hasSuperset)
            }
        }
    }

    private func exerciseRow(_ row: TemplatePreviewRow, indented: Bool) -> some View {
        let info = store?.exercise(id: row.exerciseID)
        return HStack(spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                ExerciseThumbnail(id: (info?.isCustom ?? false) ? nil : row.exerciseID)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let bodyPart = info?.bodyPart, !bodyPart.isEmpty {
                    Text(bodyPart)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !row.plan.isEmpty {
                    Text(row.plan)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
            Spacer(minLength: 0)
            Button {
                aboutExerciseID = row.exerciseID
            } label: {
                Image(systemName: "info.circle")
                    .imageScale(.large)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityLabel("About \(row.name)")
            .accessibilityIdentifier("template.exercise.about")
        }
        .padding(.vertical, 8)
        .padding(.leading, indented ? 9 : 0)
        .background(alignment: .leading) {
            if let group = row.supersetGroup {
                Capsule()
                    .fill(Color.superset(group))
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
    }
}

/// The compact-width presentation: a medium-detent sheet with its own stack and a Close item.
struct TemplatePreviewSheet: View {
    let template: Template
    let started: () -> Void
    let edit: (Template) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TemplatePreview(template: template, started: started, edit: edit)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .accessibilityLabel("Close")
                            .accessibilityIdentifier("template.preview.close")
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

#if DEBUG
    /// The first sample template's preview as the compact sheet over the Workout tab, for the gallery
    /// (`-preview TemplatePreview`); the gallery has no engine, so Start does nothing here.
    struct TemplatePreviewDemo: View {
        @Query(sort: [SortDescriptor(\Template.position), SortDescriptor(\Template.name)]) private var templates:
            [Template]
        @State private var shown: Template?

        var body: some View {
            WorkoutView()
                .sheet(item: $shown) { TemplatePreviewSheet(template: $0, started: {}, edit: { _ in }) }
                .onChange(of: templates.first?.id, initial: true) { shown = templates.first }
        }
    }
#endif
