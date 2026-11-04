//
//  SetTable.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The exercise blocks and their set rows (task 2.3), one component for the template editor, the active workout and a past
/// workout. It renders whatever its `SetTableDataSource` reports and sends every edit back; the only state it owns is the
/// keyboard focus.
///
/// Layout (`active-workout.md` section 2): one block per exercise, each a header (superset marker, name, rest caption,
/// note), a column header, the set rows and a trailing **Add Set** row, in a `LazyVStack`. A set row deletes by swipe
/// (`swipeActionsContainer()`), a block reorders by drag (`.reorderable()` + `reorderContainer`). On wide layouts the
/// content keeps a readable width and is centred.
///
/// The table does not provide a navigation container; the keyboard accessory group is a toolbar and needs the caller's.
struct SetTable: View {
    let source: any SetTableDataSource
    /// Tapping an exercise name (the logging screen opens its detail and follows it with the exercise pane).
    var onSelectExercise: (SetTableSection) -> Void = { _ in }

    @FocusState private var focus: SetRowField?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var readableWidth = 640.0
    @ScaledMetric(relativeTo: .body) private var touch = 44.0
    @ScaledMetric(relativeTo: .body) private var labelWidth = 28.0

    var body: some View {
        let sections = source.sections
        let numbers = supersetNumbers(for: sections)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(sections) { section in
                    block(section, supersetNumber: numbers[section.id])
                }
                .reorderable()
            }
            .reorderContainer(for: SetTableSection.self) { difference in
                reorder(sections, difference)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 16)
            .frame(maxWidth: readableWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .swipeActionsContainer()
        .animation(.snappy, value: sections.flatMap { $0.rows.map(\.id) })
        .setKeyboardToolbar(
            step: { direction in step(direction, in: sections) },
            previous: { if let field = focus { source.applyPrevious(to: field.setID) } },
            next: { focusNext(in: sections) },
            done: { focus = nil },
            rest: source.rest
        )
        .setHaptics(checkedSetCount: source.mode == .active ? source.checkedSetCount : 0)
        .accessibilityIdentifier("settable")
    }

    // MARK: Block

    private func block(_ section: SetTableSection, supersetNumber: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(section, supersetNumber: supersetNumber)
            if let first = section.rows.first, !dynamicTypeSize.isAccessibilitySize {
                columnHeader(for: first)
            }
            ForEach(section.rows) { row in
                SetRow(
                    model: row,
                    focus: $focus,
                    onCycleKind: { source.cycleKind(of: row.id) },
                    onApplyPrevious: { source.applyPrevious(to: row.id) },
                    onCommitWeight: { source.commitWeight($0, for: row.id) },
                    onCommitReps: { source.commitReps($0, for: row.id) },
                    onToggleCheck: { source.toggleCheck(of: row.id) }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        source.deleteSet(row.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityIdentifier("setrow.\(row.id.uuidString).delete")
                }
                .accessibilityAction(named: "Delete set") { source.deleteSet(row.id) }
            }
            addSetRow(section)
        }
        .padding(.leading, supersetNumber == nil ? 0 : 12)
        .overlay(alignment: .leading) {
            if let supersetNumber {
                Capsule()
                    .fill(Self.supersetColor(supersetNumber))
                    .frame(width: 4)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settable.section.\(section.id.uuidString)")
    }

    private func header(_ section: SetTableSection, supersetNumber: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let supersetNumber {
                Text("Superset \(supersetNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(Self.supersetColor(supersetNumber))
                    .accessibilityIdentifier("settable.superset.\(section.id.uuidString)")
            }
            Button {
                onSelectExercise(section)
            } label: {
                Text(section.name)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint("Opens the exercise")
            .accessibilityIdentifier("settable.name.\(section.id.uuidString)")
            if let rest = SetTableLayout.restCaption(seconds: section.restSeconds) {
                Text(rest)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !section.note.isEmpty {
                Text(section.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    /// Set · Previous · unit · Reps · ✓, mirroring the row's one-line columns. Hidden from VoiceOver (the cells carry their own
    /// labels) and dropped at accessibility sizes, where the row stacks into two lines.
    private func columnHeader(for row: SetRowModel) -> some View {
        HStack(spacing: 8) {
            Text("Set").frame(minWidth: labelWidth)
            if row.showsPrevious { Text("Previous").frame(maxWidth: .infinity) }
            if row.showsWeight { Text(row.unit.rawValue).frame(maxWidth: .infinity) }
            Text(row.measure == .duration ? "Time" : "Reps").frame(maxWidth: .infinity)
            if row.showsCheck { Image(systemName: "checkmark").frame(width: touch) }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
        .accessibilityHidden(true)
    }

    private func addSetRow(_ section: SetTableSection) -> some View {
        Button {
            source.addSet(to: section.id)
        } label: {
            Label("Add Set", systemImage: "plus")
                .frame(maxWidth: .infinity, minHeight: touch, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .padding(.horizontal, 8)
        .accessibilityLabel("Add set")
        .accessibilityHint("Adds a set to \(section.name)")
        .accessibilityIdentifier("settable.addset.\(section.id.uuidString)")
    }

    // MARK: Superset

    private func supersetNumbers(for sections: [SetTableSection]) -> [UUID: Int] {
        let numbers = SetTableLayout.supersetNumbers(for: sections.map(\.supersetGroup))
        var result: [UUID: Int] = [:]
        for (section, number) in zip(sections, numbers) {
            if let number { result[section.id] = number }
        }
        return result
    }

    /// Six colours by group number, wrapping (`workout.md` "Supersets"). None of them is a set-kind or check colour.
    private static func supersetColor(_ number: Int) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .teal, .indigo, .brown]
        return palette[(number - 1) % palette.count]
    }

    // MARK: Reorder

    private func reorder(
        _ sections: [SetTableSection],
        _ difference: ReorderDifference<UUID, ReorderableSingleCollectionIdentifier>
    ) {
        let destination: UUID?
        switch difference.destination.position {
        case .before(let id): destination = id
        case .end: destination = nil
        }
        source.reorder(
            SetTableLayout.reordered(sections.map(\.id), moving: difference.sources, before: destination)
        )
    }

    // MARK: Keyboard

    private func step(_ direction: SetKeyboard.Direction, in sections: [SetTableSection]) {
        guard let field = focus, let row = sections.lazy.flatMap(\.rows).first(where: { $0.id == field.setID })
        else { return }
        let text = SetKeyboard.stepped(
            field.column == .weight ? row.weightText : row.repsText,
            column: field.column,
            direction: direction,
            unit: row.unit,
            weightType: row.weightType
        )
        switch field.column {
        case .weight: source.commitWeight(SetInputFormat.parseWeight(text), for: row.id)
        case .reps: source.commitReps(SetInputFormat.parseCount(text), for: row.id)
        }
    }

    private func focusNext(in sections: [SetTableSection]) {
        guard let field = focus else { return }
        let rows = sections.flatMap(\.rows)
        focus = SetKeyboard.nextField(
            after: field,
            in: rows.map(\.id),
            weightlessSetIDs: Set(rows.filter { !$0.showsWeight }.map(\.id))
        )
    }
}

#if DEBUG
    /// The gallery entry `SetTable`: an active workout started from the first sample template, hosted in a navigation
    /// stack (the keyboard group is a toolbar). Needs the sample container and exercise store in the environment, which
    /// `PreviewGallery.host` provides.
    struct SetTableDemo: View {
        @Environment(\.modelContext) private var context
        @Environment(ExerciseStore.self) private var store
        @State private var engine: ActiveWorkoutEngine?
        @State private var failure: String?

        var body: some View {
            NavigationStack {
                Group {
                    if let engine {
                        SetTable(source: EngineSetTableSource(engine: engine, store: store))
                    } else if let failure {
                        ContentUnavailableView(
                            "Could not start the workout",
                            systemImage: "exclamationmark.triangle",
                            description: Text(failure)
                        )
                    } else {
                        ProgressView()
                    }
                }
                .navigationTitle(engine?.workout?.name ?? "Workout")
                .navigationBarTitleDisplayMode(.inline)
            }
            .task { start() }
            .accessibilityIdentifier("screen.setTable")
        }

        private func start() {
            guard engine == nil else { return }
            do {
                let engine = try ActiveWorkoutEngine(context: context, store: store, settings: SettingsStore())
                if engine.workout == nil {
                    var descriptor = FetchDescriptor<Template>(
                        sortBy: [SortDescriptor(\.position), SortDescriptor(\.name)]
                    )
                    descriptor.fetchLimit = 1
                    if let template = try context.fetch(descriptor).first {
                        try engine.start(from: template)
                    } else {
                        try engine.startEmpty()
                    }
                }
                self.engine = engine
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    #Preview("Large") {
        PreviewGallery.host("SetTable")
            .dynamicTypeSize(.large)
    }

    #Preview("Accessibility 3") {
        PreviewGallery.host("SetTable")
            .dynamicTypeSize(.accessibility3)
    }
#endif
