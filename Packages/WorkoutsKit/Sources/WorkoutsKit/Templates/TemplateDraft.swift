import Foundation
import SwiftData

/// The template editor's working copy (task 3.4): plain values read from a `Template`, edited freely, and written back in
/// one `save`. Nothing touches the model (or iCloud) until then, so Cancel is just dropping the draft. A new template is a
/// draft with no model behind it; `insertNew` creates the model on Save.
///
/// Rows and sets are matched to the model by id on save, so fields the editor does not show stay as they are.
public struct TemplateDraft: Equatable, Sendable {
    /// One planned set row of the draft.
    public struct SetValues: Equatable, Sendable, Identifiable {
        public let id: UUID
        public var kind: SetKind
        public var weight: Double?
        public var reps: Int?
        public var durationSeconds: Int?
        public var distanceMeters: Double?
    }

    /// One exercise block of the draft.
    public struct ExerciseValues: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let exerciseID: UUID
        public var name: String
        public var supersetGroup: Int?
        public var note: String
        public var restSeconds: Int?
        public var unit: WeightUnit
        public var barType: BarType
        public var barWeight: Double?
        /// Whether the reps column holds seconds. Fixed when the row is made, so clearing the one duration does not turn
        /// the block into a reps block mid-edit.
        public let isTimed: Bool
        public var sets: [SetValues]
    }

    /// The name a new template starts with.
    public static let newTemplateName = "New Template"

    /// How many empty sets a new exercise starts with (the logging screen's number).
    public static let defaultSetCount = 3

    public var name: String
    public var note: String
    public var exercises: [ExerciseValues]

    /// A new, empty template's draft.
    public init(name: String = TemplateDraft.newTemplateName) {
        self.name = name
        note = ""
        exercises = []
    }

    /// The draft of an existing template.
    public init(_ template: Template) {
        name = template.name
        note = template.note
        exercises = (template.exercises ?? [])
            .sorted { $0.position < $1.position }
            .map { row in
                let sets = (row.sets ?? []).sorted { $0.position < $1.position }
                return ExerciseValues(
                    id: row.id,
                    exerciseID: row.exerciseID,
                    name: row.exerciseName,
                    supersetGroup: row.supersetGroup,
                    note: row.note,
                    restSeconds: row.restSeconds,
                    unit: row.unit,
                    barType: row.barType,
                    barWeight: row.barWeight,
                    isTimed: sets.contains { $0.durationSeconds != nil },
                    sets: sets.map {
                        SetValues(
                            id: $0.id,
                            kind: $0.kind,
                            weight: $0.weight,
                            reps: $0.reps,
                            durationSeconds: $0.durationSeconds,
                            distanceMeters: $0.distanceMeters
                        )
                    }
                )
            }
    }

    // MARK: Header fields

    /// Renames the template; blank or whitespace-only input is ignored, anything else is trimmed.
    public mutating func rename(to text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        name = trimmed
    }

    /// Sets the template's own note, trimmed (whitespace-only clears it).
    public mutating func setNote(_ text: String) {
        note = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Set edits

    public mutating func setWeight(_ weight: Double?, for setID: UUID) {
        edit(setID) { $0.weight = weight }
    }

    /// Reps, or seconds when the set's exercise is timed.
    public mutating func setCount(_ value: Int?, for setID: UUID) {
        guard let found = locate(setID) else { return }
        if exercises[found.exercise].isTimed {
            edit(setID) { $0.durationSeconds = value }
        } else {
            edit(setID) { $0.reps = value }
        }
    }

    /// normal, W, D, F, normal.
    public mutating func cycleKind(of setID: UUID) {
        edit(setID) { $0.kind = SetInputFormat.nextKind(after: $0.kind) }
    }

    /// Appends a set that copies the last one's values (a warm-up is followed by a normal set), or an empty normal set.
    public mutating func addSet(to exerciseID: UUID, id: UUID = UUID()) {
        guard let e = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let last = exercises[e].sets.last
        exercises[e].sets.append(
            SetValues(
                id: id,
                kind: last.map { $0.kind == .warmup ? .normal : $0.kind } ?? .normal,
                weight: last?.weight,
                reps: last?.reps,
                durationSeconds: last?.durationSeconds,
                distanceMeters: last?.distanceMeters
            )
        )
    }

    public mutating func deleteSet(_ setID: UUID) {
        guard let found = locate(setID) else { return }
        exercises[found.exercise].sets.remove(at: found.set)
    }

    // MARK: Exercise edits

    /// Appends `infos` in order with their defaults: a custom exercise's own unit, bar and rest if set, else
    /// `defaultUnit`, an Olympic bar for barbells (none otherwise); rest stays nil (Default) unless the exercise has its own; three empty sets each. With
    /// `asSuperset` (and at least two exercises) they form one new superset group. Returns the new rows' ids.
    @discardableResult
    public mutating func addExercises(
        _ infos: [ExerciseInfo],
        defaultUnit: WeightUnit,
        asSuperset: Bool = false
    ) -> [UUID] {
        let added = infos.map { info in
            ExerciseValues(
                id: UUID(),
                exerciseID: info.id,
                name: info.name,
                supersetGroup: nil,
                note: "",
                restSeconds: info.restSeconds,
                unit: info.unit ?? defaultUnit,
                barType: info.barType ?? (info.weightType == .barbell ? .olympic : .none),
                barWeight: info.barWeight,
                isTimed: false,
                sets: (0..<Self.defaultSetCount).map { _ in
                    SetValues(
                        id: UUID(),
                        kind: .normal,
                        weight: nil,
                        reps: nil,
                        durationSeconds: nil,
                        distanceMeters: nil
                    )
                }
            )
        }
        exercises.append(contentsOf: added)
        let ids = added.map(\.id)
        if asSuperset, ids.count >= ExerciseSelection.supersetMinimum {
            let grouped = SupersetGrouping.grouping(
                exercises.map { (id: $0.id, group: $0.supersetGroup) },
                members: ids
            )
            for (index, item) in grouped.enumerated() { exercises[index].supersetGroup = item.group }
        }
        return ids
    }

    /// Rewrites the exercise order; ignored unless `order` holds every exercise id exactly once. A superset the move
    /// splits loses the moved block, and a block dropped inside a superset lands after it
    /// (``SupersetGrouping/reordered(_:to:moving:)``); `moving` is the dragged block ids when known.
    public mutating func reorder(_ order: [UUID], moving: [UUID] = []) {
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        guard order.count == byID.count, Set(order).count == byID.count else { return }
        guard order.compactMap({ byID[$0] }).count == byID.count else { return }
        let groups = SupersetGrouping.reordered(
            exercises.map { (id: $0.id, group: $0.supersetGroup) },
            to: order,
            moving: moving
        )
        exercises = groups.compactMap { byID[$0.id] }
        applyGroups(groups)
    }

    // MARK: Block actions (task 3.6)

    /// Sets the block's note, trimmed (whitespace-only clears it).
    public mutating func setNote(_ text: String, for blockID: UUID) {
        guard let e = index(of: blockID) else { return }
        exercises[e].note = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Add Warm-up Sets, as the logging engine does: the block's warm-up sets are replaced by the ``WarmupRamp`` for its
    /// first non-warm-up set with a weight above 0, in the block's unit and bar. The ramp sits ahead of the working sets
    /// (kind warm-up, weight and reps filled).
    ///
    /// Returns whether the block has a working weight (the UI asks for one first when it does not), not whether any
    /// warm-up was built. Without a working weight nothing changes. A working weight so light its ramp is empty (45 lb on
    /// the 45 lb bar, a 5 lb dumbbell) also changes nothing: the existing warm-ups stay, since there is no ramp to
    /// replace them with (the logging engine, which tracks completed sets, instead drops its unchecked old warm-ups).
    @discardableResult
    public mutating func addWarmupSets(to blockID: UUID, makeID: () -> UUID = UUID.init) -> Bool {
        guard let e = index(of: blockID) else { return false }
        let block = exercises[e]
        guard let weight = block.sets.first(where: { $0.kind != .warmup && ($0.weight ?? 0) > 0 })?.weight
        else { return false }
        let ramp = WarmupRamp.steps(
            workingWeight: weight,
            unit: block.unit,
            barType: block.barType,
            customBarWeight: block.barWeight
        )
        guard !ramp.isEmpty else { return true }
        let warmups = ramp.map {
            SetValues(
                id: makeID(),
                kind: .warmup,
                weight: $0.weight,
                reps: $0.reps,
                durationSeconds: nil,
                distanceMeters: nil
            )
        }
        exercises[e].sets = warmups + block.sets.filter { $0.kind != .warmup }
        return true
    }

    /// Update Rest Timers: the block's rest in seconds: 0 = Off, nil = Default (the Settings rest). The engine has no "whole
    /// superset" rule for rest (each row rests by its own length), so only this block changes.
    public mutating func updateRestTimers(_ seconds: Int?, for blockID: UUID) {
        guard let e = index(of: blockID) else { return }
        exercises[e].restSeconds = seconds
    }

    /// Preferences: the block's weight unit. Set values are not converted (the engine's rule too), but a custom bar's
    /// weight is, rounded to 0.5 like the engine.
    public mutating func setUnit(_ unit: WeightUnit, for blockID: UUID) {
        guard let e = index(of: blockID) else { return }
        if exercises[e].unit != unit, exercises[e].barType == .custom, let bar = exercises[e].barWeight {
            exercises[e].barWeight = round05(convert(bar, from: exercises[e].unit, to: unit))
        }
        exercises[e].unit = unit
    }

    /// Preferences: the block's bar. `weight` is the custom bar's weight (only a `.custom` bar reads it).
    public mutating func setBar(_ type: BarType, weight: Double?, for blockID: UUID) {
        guard let e = index(of: blockID) else { return }
        exercises[e].barType = type
        exercises[e].barWeight = weight
    }

    /// Replaces the block's exercise with `info`: id, name, unit, bar and rest take the same defaults as
    /// ``addExercises(_:defaultUnit:asSuperset:)``. The block keeps its id, position, superset group,
    /// note and sets (their values are not cleared or converted, as in the engine).
    public mutating func replaceExercise(
        _ blockID: UUID,
        with info: ExerciseInfo,
        defaultUnit: WeightUnit
    ) {
        guard let e = index(of: blockID) else { return }
        let old = exercises[e]
        exercises[e] = ExerciseValues(
            id: old.id,
            exerciseID: info.id,
            name: info.name,
            supersetGroup: old.supersetGroup,
            note: old.note,
            restSeconds: info.restSeconds,
            unit: info.unit ?? defaultUnit,
            barType: info.barType ?? (info.weightType == .barbell ? .olympic : .none),
            barWeight: info.barWeight,
            isTimed: old.isTimed,
            sets: old.sets
        )
    }

    /// Makes `blockIDs` one superset: the engine's rule (``SupersetGrouping/grouping(_:members:)``). The members are
    /// gathered where the first of them was, take a fresh group, groups left with fewer than two members dissolve and
    /// groups renumber 1, 2, 3 by first appearance. Unknown ids are ignored; fewer than two known ones only run the
    /// dissolve and renumber pass.
    public mutating func makeSuperset(_ blockIDs: [UUID]) {
        let grouped = SupersetGrouping.grouping(
            exercises.map { (id: $0.id, group: $0.supersetGroup) },
            members: blockIDs
        )
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        exercises = grouped.compactMap { item in
            byID[item.id].map { block in
                var block = block
                block.supersetGroup = item.group
                return block
            }
        }
    }

    /// Takes the block out of its superset; a group left with one member dissolves and the rest renumber. A block that is
    /// in no superset is untouched.
    public mutating func removeFromSuperset(_ blockID: UUID) {
        guard let e = index(of: blockID), exercises[e].supersetGroup != nil else { return }
        exercises[e].supersetGroup = nil
        applyGroups(SupersetGrouping.normalized(exercises.map { (id: $0.id, group: $0.supersetGroup) }))
    }

    /// Removes the block with its sets. A superset left with one member dissolves and the groups renumber 1, 2, 3
    /// (``SupersetGrouping/removing(_:from:)``).
    public mutating func removeExercise(_ blockID: UUID) {
        guard index(of: blockID) != nil else { return }
        let remaining = SupersetGrouping.removing(blockID, from: exercises.map { (id: $0.id, group: $0.supersetGroup) })
        exercises.removeAll { $0.id == blockID }
        applyGroups(remaining)
    }

    private func index(of blockID: UUID) -> Int? {
        exercises.firstIndex { $0.id == blockID }
    }

    /// Writes `groups` (same order as `exercises`) back onto the blocks.
    private mutating func applyGroups(_ groups: [(id: UUID, group: Int?)]) {
        for (position, item) in groups.enumerated() where exercises[position].id == item.id {
            exercises[position].supersetGroup = item.group
        }
    }

    private func locate(_ setID: UUID) -> (exercise: Int, set: Int)? {
        for (e, row) in exercises.enumerated() {
            if let s = row.sets.firstIndex(where: { $0.id == setID }) { return (e, s) }
        }
        return nil
    }

    private mutating func edit(_ setID: UUID, _ change: (inout SetValues) -> Void) {
        guard let found = locate(setID) else { return }
        change(&exercises[found.exercise].sets[found.set])
    }

    // MARK: Dirty

    /// Whether anything differs from `original`, the draft made when the editor opened (typing a value and reverting is
    /// clean).
    public func hasChanges(from original: TemplateDraft) -> Bool { self != original }

    // MARK: Save

    /// Writes the draft to `template` and saves `context`. On a failed save the context rolls back (so no half-applied
    /// edit is left in the store) and the error is rethrown; the draft itself is untouched and can be saved again.
    @MainActor
    public func save(to template: Template, in context: ModelContext, now: Date = .now) throws {
        apply(to: template, in: context, now: now)
        try commit(context)
    }

    /// Creates the template of a new draft, last among `siblings` in `folder` (or among the unfiled), and saves `context`.
    /// On failure the insert rolls back with everything else.
    @MainActor
    @discardableResult
    public func insertNew(
        in folder: TemplateFolder?,
        context: ModelContext,
        siblings: [Template],
        now: Date = .now
    ) throws -> Template {
        let last = siblings.filter { $0.folder?.id == folder?.id }.map(\.position).max()
        let template = Template(
            name: name,
            note: note,
            position: (last ?? -1) + 1,
            folder: folder,
            createdAt: now,
            updatedAt: now
        )
        context.insert(template)
        apply(to: template, in: context, now: now)
        try commit(context)
        return template
    }

    @MainActor
    private func commit(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Writes the draft to `template` without saving. Rows and sets are matched by id: kept ones are updated in place,
    /// new ones inserted, removed ones deleted. The template and a row are stamped only when their values changed.
    @MainActor
    public func apply(to template: Template, in context: ModelContext, now: Date = .now) {
        let before = TemplateDraft(template)
        if before != self { template.updatedAt = now }
        template.name = name
        template.note = note

        let rows = Dictionary(uniqueKeysWithValues: (template.exercises ?? []).map { ($0.id, $0) })
        let keptIDs = Set(exercises.map(\.id))
        for (id, row) in rows where !keptIDs.contains(id) { context.delete(row) }

        for (position, values) in exercises.enumerated() {
            let row: TemplateExercise
            if let found = rows[values.id] {
                row = found
                if before.exercises.first(where: { $0.id == values.id }) != values { row.updatedAt = now }
            } else {
                row = TemplateExercise(id: values.id, template: template, updatedAt: now)
                context.insert(row)
            }
            row.exerciseID = values.exerciseID
            row.exerciseName = values.name
            row.position = position
            row.supersetGroup = values.supersetGroup
            row.note = values.note
            row.restSeconds = values.restSeconds
            row.unit = values.unit
            row.barType = values.barType
            row.barWeight = values.barWeight

            let existing = Dictionary(uniqueKeysWithValues: (row.sets ?? []).map { ($0.id, $0) })
            let setIDs = Set(values.sets.map(\.id))
            for (id, set) in existing where !setIDs.contains(id) { context.delete(set) }
            for (index, set) in values.sets.enumerated() {
                let model: TemplateSet
                if let found = existing[set.id] {
                    model = found
                } else {
                    model = TemplateSet(id: set.id, templateExercise: row)
                    context.insert(model)
                }
                model.position = index
                model.kind = set.kind
                model.weight = set.weight
                model.reps = set.reps
                model.durationSeconds = set.durationSeconds
                model.distanceMeters = set.distanceMeters
            }
        }
    }
}
