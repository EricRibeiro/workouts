//
//  TemplateCard.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// What a card's context menu can do (task 3.2b). The screen owns the work (errors, the delete confirmation, the editor
/// push); the card only offers it.
struct TemplateCardActions {
    /// Every folder in order, for the Move submenu.
    var folders: [TemplateFolder] = []
    var edit: (Template) -> Void = { _ in }
    var duplicate: (Template) -> Void = { _ in }
    /// Moves to the end of that folder (nil: unfiled).
    var move: (Template, TemplateFolder?) -> Void = { _, _ in }
    /// Asks first; the screen shows the confirmation.
    var delete: (Template) -> Void = { _ in }
}

/// A folder's templates as Fitness-shaped cards in even columns (task 3.2a). The columns come from the grid's own width
/// (`EvenColumnGrid`), so on the open Duo the gutter falls on the fold; at the closed Duo's width it is two.
struct TemplateGrid: View {
    let templates: [Template]
    /// Built once by the screen (one pass over the finished workouts), not per card.
    let lastPerformed: TemplateCardSummary.LastPerformedIndex
    let namespace: Namespace.ID
    let open: (Template) -> Void
    var actions = TemplateCardActions()

    var body: some View {
        EvenColumnGrid(minimum: 160) {
            ForEach(templates) { template in
                TemplateCard(
                    template: template,
                    summary: TemplateCardSummary.make(for: template, index: lastPerformed),
                    namespace: namespace,
                    actions: actions,
                    open: { open(template) }
                )
            }
        }
    }
}

/// One template as a card: the shared dashboard container (fill, no rim, 20 pt corners), a title row (name and
/// `chevron.right`), then four text levels: the name (headline), the exercise count (subheadline, tinted), the first
/// exercises (footnote) and when it was last performed (caption). Members of a superset wear that group's bar. One
/// accessibility element, a button.
struct TemplateCard: View {
    let template: Template
    let summary: TemplateCardSummary
    let namespace: Namespace.ID
    let actions: TemplateCardActions
    let open: () -> Void

    /// At accessibility sizes the exercise lines wrap rather than truncate (the real names fit at accessibility3).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hasSuperset: Bool { summary.lines.contains { $0.supersetGroup != nil } }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(summary.countText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
                if !summary.lines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(summary.lines) { line in
                            Text(line.text)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                .padding(.leading, hasSuperset ? 9 : 0)
                                .background(alignment: .leading) {
                                    if let group = line.supersetGroup {
                                        Capsule()
                                            .fill(Color.superset(group))
                                            .frame(width: 3)
                                    }
                                }
                        }
                        if let more = summary.overflowText {
                            Text(more)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.leading, hasSuperset ? 9 : 0)
                        }
                    }
                }
                if let last = summary.lastPerformed {
                    Text("Last performed · \(last)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .dashboardCardStyle()
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: template.id, in: namespace)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel(name: template.name))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("workout.template.\(template.id.uuidString)")
    }
}

extension TemplateCard {
    /// Edit, Duplicate, Move, then Delete. There is no ⋯ button and no swipe: a grid has no swipe actions, so the
    /// long-press menu is the one path.
    @ViewBuilder
    fileprivate var menu: some View {
        Button("Edit", systemImage: "pencil") { actions.edit(template) }
            .accessibilityLabel("Edit")
            .accessibilityIdentifier("templateCard.edit")
        Button("Duplicate", systemImage: "plus.square.on.square") { actions.duplicate(template) }
            .accessibilityLabel("Duplicate")
            .accessibilityIdentifier("templateCard.duplicate")
        if !actions.folders.isEmpty {
            Menu("Move", systemImage: "folder") {
                ForEach(actions.folders) { folder in
                    let isCurrent = template.folder?.id == folder.id
                    Button(folder.name, systemImage: isCurrent ? "checkmark" : "folder") {
                        actions.move(template, folder)
                    }
                    .disabled(isCurrent)
                    .accessibilityLabel(folder.name)
                    .accessibilityIdentifier("templateCard.move.\(folder.id.uuidString)")
                }
                let isUnfiled = template.folder == nil
                Button("No Folder", systemImage: isUnfiled ? "checkmark" : "tray") {
                    actions.move(template, nil)
                }
                .disabled(isUnfiled)
                .accessibilityLabel("No Folder")
                .accessibilityIdentifier("templateCard.move.none")
            }
            .accessibilityLabel("Move")
            .accessibilityIdentifier("templateCard.move")
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { actions.delete(template) }
            .accessibilityLabel("Delete")
            .accessibilityIdentifier("templateCard.delete")
    }
}
