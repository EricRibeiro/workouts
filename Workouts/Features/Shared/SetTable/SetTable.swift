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
    /// The header's options menu (note, warm-ups, rest, reorder, remove); nil shows no menu.
    var blockActions: SetTableBlockActions? = nil

    @FocusState private var focus: SetRowField?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    private var defaultRestSeconds: Int { settings?.defaultRestSeconds ?? SettingsStore.defaultRestSecondsDefault }
    @ScaledMetric(relativeTo: .body) private var readableWidth = 640.0
    @ScaledMetric(relativeTo: .body) private var touch = 44.0
    @ScaledMetric(relativeTo: .body) private var labelWidth = 28.0

    var body: some View {
        let sections = source.sections
        let numbers = SetTableSection.supersetNumbers(for: sections)
        let order = sections.map(\.id)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(sections) { section in
                        block(section, supersetNumber: numbers[section.id], order: order)
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
                revealFocusedRow(proxy)
            }
            // The keyboard inset settles after the focus change when the keyboard is still animating (a tap on another
            // cell while a check or Done dismissal is in flight), so the one scroll above was computed against a stale
            // inset; centre again whenever it grows. Only growth: an interactive drag-to-dismiss shrinks it while the
            // field is still focused, and re-centring then would fight the drag.
            .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.bottom.rounded() }) { old, new in
                if new > old { revealFocusedRow(proxy) }
            }
        }
        .swipeActionsContainer()
        // The table leaving the screen (cover minimised) with a field still focused.
        .onDisappear { source.commitEdits() }
        .animation(.snappy, value: sections.flatMap { $0.rows.map(\.id) })
        .setKeyboardToolbar(
            step: { direction in step(direction, in: sections) },
            // Only the active workout has a previous set to copy; the template and past editors get no Previous key.
            previous: source.mode == .active
                ? { if let field = focus { source.applyPrevious(to: field.setID) } } : nil,
            next: { focusNext(in: sections) },
            done: { focus = nil },
            rest: source.rest,
            stepDescription: stepDescription(in: sections)
        )
        .setHaptics(checkedSetCount: source.mode == .active ? source.checkedSetCount : 0)
        .preference(key: SetTableEditingKey.self, value: focus != nil)
        .accessibilityIdentifier("settable")
    }

    // MARK: Block

    private func block(_ section: SetTableSection, supersetNumber: Int?, order: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(section, supersetNumber: supersetNumber, order: order)
            // At accessibility sizes a row with a Previous line stacks (the cells carry captions instead); one without it
            // (template and past editors) stays on one line, so the header still applies.
            if let first = section.rows.first, !dynamicTypeSize.isAccessibilitySize || !first.showsPrevious {
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
                    onToggleCheck: { toggleCheck(row) },
                    onDelete: { source.deleteSet(row.id) }
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
            }
            addSetRow(section)
        }
        .padding(.leading, supersetNumber == nil ? 0 : 12)
        .overlay(alignment: .leading) {
            if let supersetNumber {
                Capsule()
                    .fill(Self.supersetColor(supersetNumber))
                    .frame(width: Metrics.supersetBarWidth)
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

    private func header(_ section: SetTableSection, supersetNumber: Int?, order: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let supersetNumber {
                Text("Superset \(supersetNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(Self.supersetColor(supersetNumber))
                    .accessibilityIdentifier("settable.superset.\(section.id.uuidString)")
            }
            // The menu's glyph shares the name's first line (its centre on the line's centre) while its frame keeps 44 pt.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
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
                .accessibilityActions {
                    // Only where the move is possible: no "Move up" on the first block, no "Move down" on the last.
                    if SetTableLayout.moved(order, id: section.id, by: -1) != nil {
                        Button("Move up") { moveBlock(section.id, order, by: -1) }
                    }
                    if SetTableLayout.moved(order, id: section.id, by: 1) != nil {
                        Button("Move down") { moveBlock(section.id, order, by: 1) }
                    }
                }
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
            if !section.note.isEmpty {
                SetTableNoteLine(
                    text: section.note,
                    identifier: "settable.note.\(section.id.uuidString)",
                    onEdit: blockActions.map { actions in { actions.note(section.id) } }
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    /// The header's trailing options menu. The entries are the owner's; the table only lays them out.
    private func blockMenu(_ section: SetTableSection, actions: SetTableBlockActions) -> some View {
        let hasSets = actions.addWarmups != nil || actions.updateRest != nil
        let hasExercise =
            onSelectExercise != nil || actions.replace != nil || actions.superset != nil || actions.preferences != nil
        // Groups separated by Dividers, not `Section`s: a Section drops the buttons' accessibility identifiers (the menu
        // items then show only their labels, and the UI tests find them by identifier).
        return Menu {
            Group {
                Button("Note…", systemImage: "note.text") { actions.note(section.id) }
                    .accessibilityIdentifier("settable.menu.note")
            }
            if hasSets {
                Divider()
                Group {
                    if let addWarmups = actions.addWarmups {
                        Button("Add Warm-up Sets", systemImage: "flame") { addWarmups(section.id) }
                            .accessibilityIdentifier("settable.menu.warmup")
                    }
                    if let updateRest = actions.updateRest {
                        Button("Update Rest Timer…", systemImage: "timer") { updateRest(section.id) }
                            .accessibilityIdentifier("settable.menu.rest")
                    }
                }
            }
            if hasExercise {
                Divider()
                Group {
                    if let onSelectExercise {
                        Button("Exercise Info", systemImage: "info.circle") { onSelectExercise(section) }
                            .accessibilityIdentifier("settable.menu.info")
                    }
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
                }
            }
            if let reorder = actions.reorder {
                Divider()
                Group {
                    Button("Reorder Exercises…", systemImage: "arrow.up.arrow.down") { reorder() }
                        .disabled(source.sections.count < 2)
                        .accessibilityIdentifier("settable.menu.reorder")
                }
            }
            if let remove = actions.remove {
                Divider()
                Group {
                    Button("Remove Exercise", systemImage: "trash", role: .destructive) { remove(section.id) }
                        .accessibilityIdentifier("settable.menu.remove")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                // Centred over the check column; with no check column (template and past editors) the cells run to the
                // trailing edge, so the glyph aligns there. The hit target stays `touch` wide either way.
                .frame(
                    minWidth: touch,
                    minHeight: touch,
                    alignment: section.rows.first?.showsCheck == false ? .trailing : .center
                )
                .contentShape(.rect)
                // For the header's first-baseline alignment: a baseline 6 pt below the glyph's centre puts the circle's
                // centre on the name's x-height centre instead of sitting it on the baseline.
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
        }
        .accessibilityLabel("\(section.name) options")
        .accessibilityIdentifier("settable.menu.\(section.id.uuidString)")
    }

    /// Set · Previous · unit · Reps · ✓, mirroring the row's one-line columns. Hidden from VoiceOver (the cells carry their own
    /// labels) and dropped at accessibility sizes where the row stacks into two lines (a row with a Previous column).
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
        .padding(.horizontal, 8)
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

    /// The palette is shared with the History detail (`Color.superset(_:)`).
    private static func supersetColor(_ number: Int) -> Color {
        Color.superset(number)
    }

    // MARK: Reorder

    /// The accessibility "Move Up" / "Move Down" actions of a block header: the drag's alternative, through the same
    /// `source.reorder` path (`SetTableLayout.moved` builds the order the drag's `reordered` would).
    private func moveBlock(_ id: UUID, _ order: [UUID], by offset: Int) {
        guard let moved = SetTableLayout.moved(order, id: id, by: offset) else { return }
        source.reorder(moved, moving: [id])
    }

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
            SetTableLayout.reordered(sections.map(\.id), moving: difference.sources, before: destination),
            moving: difference.sources
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
            weightType: row.weightType,
            placeholder: field.column == .weight ? row.weightPlaceholder : row.repsPlaceholder,
            measure: row.measure
        )
        switch field.column {
        case .weight: source.commitWeight(SetInputFormat.parseWeight(text), for: row.id)
        case .reps:
            let value =
                row.measure == .duration ? SetInputFormat.parseDurationText(text) : SetInputFormat.parseCount(text)
            source.commitReps(value, for: row.id)
        }
        // VoiceOver stays on the − / + key, so say what the field now holds.
        let spoken: String
        switch field.column {
        case .weight: spoken = "Weight \(text) \(row.unit == .kg ? "kilograms" : "pounds")"
        case .reps: spoken = "\(row.measure == .duration ? "Duration \(text)" : "Reps \(text)")"
        }
        AccessibilityNotification.Announcement(spoken).post()
    }

    /// The focused field's step as spoken, for the keyboard's − / + labels.
    private func stepDescription(in sections: [SetTableSection]) -> String {
        guard let field = focus, let row = sections.lazy.flatMap(\.rows).first(where: { $0.id == field.setID })
        else { return "one step" }
        return SetKeyboard.stepDescription(
            column: field.column,
            unit: row.unit,
            weightType: row.weightType,
            measure: row.measure
        )
    }

    /// Checking a set (not unchecking, not a refused check) clears the focus, so the keyboard goes down and the rest countdown
    /// and the table are uncovered (PLAN 7.7). Only this in-app tap dismisses: the Live Activity intent runs outside the view.
    private func toggleCheck(_ row: SetRowModel) -> Bool {
        let wasChecked = row.isChecked
        let accepted = source.toggleCheck(of: row.id)
        if accepted && !wasChecked { focus = nil }
        return accepted
    }

    /// Keyboard avoidance lifts the content above the keyboard but not above the floating keyboard toolbar pill, which
    /// would hide the focused row; centring it keeps it clear of both.
    private func revealFocusedRow(_ proxy: ScrollViewProxy) {
        guard let field = focus else { return }
        withAnimation(.snappy) { proxy.scrollTo(field.setID, anchor: .center) }
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
                let engine = try ActiveWorkoutEngine(
                    context: context,
                    store: store,
                    settings: SettingsStore(),
                    timedByDefault: { [store] in store.exercise(id: $0)?.isTimed ?? false }
                )
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
