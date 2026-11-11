//
//  TemplateCard.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// What a card can do (task 3.2b): its context menu and the play button. The screen owns the work (errors, the delete
/// confirmation, the editor push, the start flow); the card only offers it.
struct TemplateCardActions {
    /// Every folder in order, for the Move submenu.
    var folders: [TemplateFolder] = []
    var edit: (Template) -> Void = { _ in }
    var duplicate: (Template) -> Void = { _ in }
    /// Moves to the end of that folder (nil: unfiled).
    var move: (Template, TemplateFolder?) -> Void = { _, _ in }
    /// Asks first; the screen shows the confirmation.
    var delete: (Template) -> Void = { _ in }
    /// The play button: starts a workout from the template, the same path as the preview's Start Workout.
    var start: (Template) -> Void = { _ in }
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
                    summary: TemplateCardSummary.make(for: template, index: lastPerformed, maxLines: 3),
                    namespace: namespace,
                    actions: actions,
                    open: { open(template) }
                )
            }
        }
    }
}

/// One template as a card on the History dashboard's surface: the name (title3 bold) with the lime play button centred
/// on its first line, the first exercises one per line (superset bar, "+ N more"), then one secondary line (exercise
/// count, and when it was last performed) pinned to the bottom. The surface is a button that opens the preview; the
/// play button is its own button, floated over the card, that starts the workout. At accessibility sizes the play
/// button drops below the name.
struct TemplateCard: View {
    let template: Template
    let summary: TemplateCardSummary
    let namespace: Namespace.ID
    let actions: TemplateCardActions
    let open: () -> Void

    @ScaledMetric(relativeTo: .title3) private var playSize: CGFloat = 36
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The play button's tap target: never under 44 pt, whatever the circle's size.
    private var playHit: CGFloat { max(playSize, 44) }
    private var hasSuperset: Bool { summary.lines.contains { $0.supersetGroup != nil } }
    private var titleFont: Font { .title3.weight(.bold) }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                titleRow
                exerciseLines
                Spacer(minLength: 0)
                meta
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Metrics.cardPadding)
            .cardBackground()
            .cardContentShape()
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: template.id, in: namespace)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel(name: template.name))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("workout.template.\(template.id.uuidString)")
        .overlay(alignment: .topTrailing) { playOverlay }
    }

    private var titleText: Text {
        Text(template.name).font(titleFont)
    }

    /// The name, with room kept for the play button: beside it, or (accessibility sizes) a row below it.
    @ViewBuilder
    private var titleRow: some View {
        let title =
            titleText
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                title
                Color.clear.frame(height: playHit)
            }
        } else {
            title
                .padding(.trailing, playHit + 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The play button floats over the card (a button cannot nest in the card's button), placed where the title row
    /// leaves its slot: centred on the title's first line, or below the name at accessibility sizes.
    @ViewBuilder
    private var playOverlay: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    titleText.lineLimit(2).multilineTextAlignment(.leading).hidden()
                    playButton
                }
            } else {
                // A hidden one-line title is the slot, so the button centres on the first line; the negative padding puts
                // the circle (not its larger tap target) on the card's padding edge.
                Text("0")
                    .font(titleFont)
                    .hidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .overlay(alignment: .trailing) { playButton }
                    .padding(.trailing, -(playHit - playSize) / 2)
            }
        }
        .padding(Metrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var playButton: some View {
        let isEmpty = summary.exerciseCount == 0
        return Button {
            actions.start(template)
        } label: {
            Circle()
                .fill(.tint)
                .frame(width: playSize, height: playSize)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.onAccent)
                }
                .frame(width: playHit, height: playHit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isEmpty)
        .opacity(isEmpty ? 0.4 : 1)
        .accessibilityLabel("Start \(template.name)")
        .accessibilityIdentifier("template.\(template.id.uuidString).start")
    }

    @ViewBuilder
    private var exerciseLines: some View {
        if !summary.lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(summary.lines) { line in
                    Text(line.text)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .truncationMode(.tail)
                        .padding(.leading, hasSuperset ? Metrics.supersetBarIndent : 0)
                        .background(alignment: .leading) {
                            if let group = line.supersetGroup {
                                Capsule()
                                    .fill(Color.superset(group))
                                    .frame(width: Metrics.supersetBarWidth)
                            }
                        }
                }
                if let more = summary.overflowText {
                    Text(more)
                        .padding(.leading, hasSuperset ? Metrics.supersetBarIndent : 0)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
        }
    }

    /// "6 exercises · Yesterday" on one line, or stacked without the dot when that does not fit.
    private var meta: some View {
        ViewThatFits(in: .horizontal) {
            Text(oneLineMeta)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.countText)
                if let last = summary.lastPerformed { Text(last) }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
    }

    private var oneLineMeta: String {
        guard let last = summary.lastPerformed else { return summary.countText }
        return "\(summary.countText) · \(last)"
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
