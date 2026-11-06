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
/// True while a set cell has keyboard focus. The logging screen reads it to thin its trailing toolbar strip, which the number
/// pad leaves too short for every item (see `ActiveWorkoutCover`).
struct SetTableEditingKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

struct SetTable: View {
    let source: any SetTableDataSource
    /// Opens the exercise's detail: called by a tap on its name and by the block menu's Exercise Info entry. Nil (the
    /// template and past-workout editors, and the logging screen at regular width, where the exercise pane follows the
    /// focus) leaves the name a plain focus target and drops the menu entry.
    var onSelectExercise: ((SetTableSection) -> Void)? = nil
    /// Reports the block (`SetTableSection.id`) of the last focused cell or tapped header, so the logging screen's exercise
    /// pane can follow it. Never reset by the table: a dismissed keyboard keeps the last exercise.
    var focusedSection: Binding<UUID?> = .constant(nil)
    /// The header's options menu (note, sticky note, warm-ups, rest, remove); nil shows no menu.
    var blockActions: SetTableBlockActions? = nil

    @FocusState private var focus: SetRowField?
    /// Every sticky note (a handful), so a header shows its exercise's note and follows edits made in the exercise pane.
    @Query private var stickyNotes: [StickyNote]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    private var defaultRestSeconds: Int { settings?.defaultRestSeconds ?? SettingsStore.defaultRestSecondsDefault }
    @ScaledMetric(relativeTo: .body) private var readableWidth = 640.0
    @ScaledMetric(relativeTo: .body) private var touch = 44.0
    @ScaledMetric(relativeTo: .body) private var labelWidth = 28.0

    var body: some View {
        let sections = source.sections
        let numbers = supersetNumbers(for: sections)
        ScrollViewReader { proxy in
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
            .onChange(of: focus) { previous, field in
                // Focus left a cell (another cell, Next/Previous, Done, the keyboard hidden): the commit point for typing.
                if previous != nil, previous != field { source.commitEdits() }
                guard let field,
                    let section = sections.first(where: { $0.rows.contains { $0.id == field.setID } })
                else { return }
                focusedSection.wrappedValue = section.id
                // Keyboard avoidance lifts the content above the keyboard but not above the floating keyboard toolbar
                // pill, which would hide the focused row; centring it keeps it clear of both.
                withAnimation(.snappy) { proxy.scrollTo(field.setID, anchor: .center) }
            }
        }
        .swipeActionsContainer()
        // The table leaving the screen (cover minimised) with a field still focused.
        .onDisappear { source.commitEdits() }
        .animation(.snappy, value: sections.flatMap { $0.rows.map(\.id) })
        .setKeyboardToolbar(
            step: { direction in step(direction, in: sections) },
            previous: { if let field = focus { source.applyPrevious(to: field.setID) } },
            next: { focusNext(in: sections) },
            done: { focus = nil },
            rest: source.rest
        )
        .setHaptics(checkedSetCount: source.mode == .active ? source.checkedSetCount : 0)
        .preference(key: SetTableEditingKey.self, value: focus != nil)
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
                .id(row.id)
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

    /// The exercise name. In the active workout it is one line with a tail ellipsis (the full name is in the info sheet; two lines at
    /// accessibility sizes); the template and past editors wrap. When it opens the exercise, a trailing chevron stays visible after
    /// truncation. The Button gives the whole thing one accessibility element labelled with the full name.
    private func nameLabel(_ section: SetTableSection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(section.name)
                .exerciseNameLineLimit(source.mode == .active)
                .layoutPriority(0)
            if onSelectExercise != nil {
                Image(systemName: "chevron.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .layoutPriority(1)
                    .accessibilityHidden(true)
            }
        }
    }

    private func header(_ section: SetTableSection, supersetNumber: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let supersetNumber {
                Text("Superset \(supersetNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(Self.supersetColor(supersetNumber))
                    .accessibilityIdentifier("settable.superset.\(section.id.uuidString)")
            }
            HStack(alignment: .top, spacing: 0) {
                Button {
                    focusedSection.wrappedValue = section.id
                    onSelectExercise?(section)
                } label: {
                    nameLabel(section)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.name)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint(onSelectExercise == nil ? "" : "Opens the exercise")
                .accessibilityIdentifier("settable.name.\(section.id.uuidString)")
                if let blockActions {
                    blockMenu(section, actions: blockActions)
                }
            }
            // The template editor shows the rest; during a workout it is only in the block menu's Update Rest Timer.
            if source.mode == .template {
                Text(SetTableLayout.restCaption(seconds: section.restSeconds, defaultSeconds: defaultRestSeconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let sticky = stickyNote(for: section) {
                Text(sticky)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.stickyNote, in: .rect(cornerRadius: 8))
                    .accessibilityLabel("Sticky note: \(sticky)")
                    .accessibilityIdentifier("settable.sticky.\(section.id.uuidString)")
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

    /// The header's trailing options menu. The entries are the owner's; the table only lays them out.
    private func blockMenu(_ section: SetTableSection, actions: SetTableBlockActions) -> some View {
        Menu {
            if let onSelectExercise {
                Button("Exercise Info", systemImage: "info.circle") { onSelectExercise(section) }
                    .accessibilityIdentifier("settable.menu.info")
            }
            Button("Note…", systemImage: "note.text") { actions.note(section.id) }
                .accessibilityIdentifier("settable.menu.note")
            Button("Sticky Note…", systemImage: "note.text.badge.plus") { actions.stickyNote(section.id) }
                .accessibilityIdentifier("settable.menu.stickyNote")
            Button("Add Warm-up Sets", systemImage: "flame") { actions.addWarmups(section.id) }
                .accessibilityIdentifier("settable.menu.warmup")
            Button("Update Rest Timer…", systemImage: "timer") { actions.updateRest(section.id) }
                .accessibilityIdentifier("settable.menu.rest")
            if let replace = actions.replace {
                Button("Replace Exercise…", systemImage: "arrow.triangle.2.circlepath") { replace(section.id) }
                    .accessibilityIdentifier("settable.menu.replace")
            }
            if let superset = actions.superset {
                Button("Superset…", systemImage: "link") { superset(section.id) }
                    .accessibilityIdentifier("settable.menu.superset")
            }
            if let preferences = actions.preferences {
                Button("Preferences…", systemImage: "slider.horizontal.3") { preferences(section.id) }
                    .accessibilityIdentifier("settable.menu.preferences")
            }
            Divider()
            Button("Remove Exercise", systemImage: "trash", role: .destructive) { actions.remove(section.id) }
                .accessibilityIdentifier("settable.menu.remove")
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: touch, minHeight: touch)
                .contentShape(.rect)
        }
        .accessibilityLabel("\(section.name) options")
        .accessibilityIdentifier("settable.menu.\(section.id.uuidString)")
    }

    private func stickyNote(for section: SetTableSection) -> String? {
        stickyNotes.first { $0.exerciseID == section.exerciseID && !$0.text.isEmpty }?.text
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

    /// The palette is shared with the History detail (`Color.superset(_:)`).
    private static func supersetColor(_ number: Int) -> Color {
        Color.superset(number)
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
