//
//  SetTableDataSource.swift
//  Workouts
//

import Foundation
import WorkoutsKit

/// Which of the three owners a `SetTable` edits (`DECISIONS.md` "SetTable").
enum SetTableMode: Hashable {
    /// A template being edited: planned weights and reps, no Previous column, no check.
    case template
    /// The workout in progress: Previous, plan placeholders, check.
    case active
    /// A finished workout being edited from History: values only.
    case past
}

/// One exercise block of the table: header values plus its set rows. Built by a data source; the table never sees a model
/// object.
struct SetTableSection: Identifiable, Hashable {
    /// The exercise row's own id (workout / template exercise), stable across edits and the target of reordering.
    let id: UUID
    /// The library or custom exercise this row is for (opens the exercise detail).
    var exerciseID: UUID
    var name: String
    /// The raw superset group of the model; the table renumbers it for display (`SetTableLayout.supersetNumbers`).
    var supersetGroup: Int?
    var note: String = ""
    var restSeconds: Int?
    var rows: [SetRowModel]
}

extension SetTableSection {
    /// Display numbers of the supersets by section id (`SetTableLayout.supersetNumbers`); sections outside a superset are absent.
    static func supersetNumbers(for sections: [SetTableSection]) -> [UUID: Int] {
        let numbers = SetTableLayout.supersetNumbers(for: sections.map(\.supersetGroup))
        var result: [UUID: Int] = [:]
        for (section, number) in zip(sections, numbers) {
            if let number { result[section.id] = number }
        }
        return result
    }
}

/// A rest in progress as the keyboard group shows it (`DECISIONS.md` "Rest UI"): when it ends and the two actions. The table
/// stays engine-agnostic; only the active source supplies one.
struct SetTableRest {
    let endsAt: Date
    let skip: () -> Void
    let add30: () -> Void
}

/// What `SetTable` needs from its owner, in the same shape for every mode. Rows are addressed by `SetRowModel.id`, sections
/// by `SetTableSection.id`. Actions are fire-and-forget: the source persists, then the table re-reads `sections`, so the
/// view never holds state of its own besides focus. Implementations are observable through the models they read (the
/// engine is `@Observable`, SwiftData models are too), so a change re-renders the table.
protocol SetTableDataSource {
    var mode: SetTableMode { get }
    /// The exercise blocks in display order.
    var sections: [SetTableSection] { get }
    /// Checked sets in the whole table; feeds the check haptic.
    var checkedSetCount: Int { get }

    /// normal → W → D → F → normal.
    func cycleKind(of setID: UUID)
    /// Copies the set's Previous values into it (active only).
    func applyPrevious(to setID: UUID)
    /// Typing: the value goes into the model per keystroke; it is written by ``commitEdits()``.
    func commitWeight(_ weight: Double?, for setID: UUID)
    /// Reps, or seconds when the row's measure is `.duration`.
    func commitReps(_ value: Int?, for setID: UUID)
    /// Writes what was typed (focus left a cell, Done); a no-op for sources that save on every edit.
    func commitEdits()
    /// Checks or unchecks (active only). Returns `false` when the engine refused (a set with nothing to record); the row then
    /// shows the refusal. Template and past sources do nothing and return `true`.
    @discardableResult
    func toggleCheck(of setID: UUID) -> Bool
    func addSet(to sectionID: UUID)
    func deleteSet(_ setID: UUID)
    /// Rewrites the exercise order; `order` holds every section id exactly once, `moving` the dragged section ids.
    func reorder(_ order: [UUID], moving: [UUID])
    /// The rest running now, or nil; the keyboard group shows it with Skip and +30 s.
    var rest: SetTableRest? { get }
}

extension SetTableDataSource {
    var checkedSetCount: Int { 0 }
    func commitEdits() {}
    var rest: SetTableRest? { nil }
}
