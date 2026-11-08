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
    /// False until the first index load lands: "Last performed" is a redacted stand-in until then, so Start Workout and
    /// the list do not jump when the line arrives.
    @State private var indexLoaded = false
    @State private var flow = StartWorkoutFlow()
    /// The exercise whose info sheet the row's `info.circle` opens (the same sheet as the active workout's; a sheet rather
    /// than a push, which also sidesteps value links never activating when this view is itself pushed at regular width).
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
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") { edit(template) }
                    .accessibilityLabel("Edit")
                    .accessibilityIdentifier("template.edit")
            }
        }
        .exerciseInfoSheet(exerciseID: $aboutExerciseID)
        .task(id: FinishedWorkoutsStamp(newestEdit: newest.first?.updatedAt, generation: generation?.value ?? 0)) {
            await SlowLoads.delay()
            // The reader's context reads the store: flush edits the main context has not saved yet.
            context.saveIfChanged(reportingTo: errors)
            let index = try? await WorkoutStatsReader.loadLastPerformedIndex(in: context.container)
            guard !Task.isCancelled else { return }
            if let index { lastPerformedIndex = index }
            indexLoaded = true
        }
        .accessibilityIdentifier("template.preview")
    }

    // MARK: Header

    private func header(lastPerformed: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let folder = template.folder {
                Label(folder.name, systemImage: "folder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !indexLoaded {
                Label("Last performed · Yesterday", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("template.preview.lastPerformed.loading")
            } else if let lastPerformed {
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
                    .exerciseNameLineLimit()
                if let bodyPart = info?.bodyPart, !bodyPart.isEmpty {
                    Text(
                        store.map { ExerciseFilter.bodyPartLabel(bodyPart, labels: $0.catalog.labels) } ?? bodyPart
                    )
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
            .foregroundStyle(.secondary)
            .accessibilityLabel("About \(row.name)")
            .accessibilityIdentifier("template.exercise.about")
        }
        .padding(.vertical, 8)
        .padding(.leading, indented ? Metrics.supersetBarIndent : 0)
        .background(alignment: .leading) {
            if let group = row.supersetGroup {
                Capsule()
                    .fill(Color.superset(group))
                    .frame(width: Metrics.supersetBarWidth)
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
        // Like every other sheet: a centered card on the regular-width Duo, the detents on compact.
        .presentationPlacement(.center)
        // A failed Start is reported by the root's alert, which sits under this sheet: host the alert here.
        .sheetSaveErrorHost()
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
