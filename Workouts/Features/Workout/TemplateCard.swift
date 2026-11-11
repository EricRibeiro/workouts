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
/// (`EvenColumnGrid`), so on the open Duo the gutter falls on the fold; at the closed Duo's width it is two. The line count
/// follows the grid's horizontal size class (three compact, six regular); each card decides by its own width whether its
/// lines carry their sets.
struct TemplateGrid: View {
    let templates: [Template]
    /// Built once by the screen (one pass over the finished workouts), not per card.
    let lastPerformed: TemplateCardSummary.LastPerformedIndex
    let namespace: Namespace.ID
    let open: (Template) -> Void
    var actions = TemplateCardActions()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var size: TemplateCard.Size { horizontalSizeClass == .regular ? .regular : .compact }

    var body: some View {
        EvenColumnGrid(minimum: size == .regular ? 280 : 160) {
            ForEach(templates) { template in
                TemplateCard(
                    template: template,
                    summary: TemplateCardSummary.make(
                        for: template,
                        index: lastPerformed,
                        maxLines: size == .regular ? 6 : 3
                    ),
                    size: size,
                    namespace: namespace,
                    actions: actions,
                    open: { open(template) }
                )
            }
        }
    }
}

/// One template as a card on the History dashboard's surface: the name (headline) with the lime play button centred
/// on its first line, the first exercises one name per line, without a set count so a narrow card keeps more of each name (superset bar, "+ N more"), then a footer pinned to the bottom:
/// when the template was last performed in the primary colour (nothing for one never performed; "No exercises" in
/// secondary for an empty one). The exercise count lives in the VoiceOver label; the exercise lines are its custom content. The surface is a button that opens the preview; the
/// play button is its own button, floated over the card, that starts the workout. At accessibility sizes the play
/// button drops below the name. A card wide enough for it (`wideThreshold`, measured, not the size class) adds each
/// exercise's sets on the trailing edge of its line and the last session's duration to the footer. Superset bars hang in
/// the card's leading padding, so every name starts on the title's edge.
struct TemplateCard: View {
    /// The line count: compact shows three names, regular six. Whether the sets and the duration show follows the card's
    /// width.
    enum Size: Sendable {
        case compact
        case regular
    }

    let template: Template
    let summary: TemplateCardSummary
    var size: Size = .compact
    let namespace: Namespace.ID
    let actions: TemplateCardActions
    let open: () -> Void

    @ScaledMetric(relativeTo: .headline) private var playSize: CGFloat = 28
    /// The card width from which each line carries its sets and the footer its duration.
    @ScaledMetric(relativeTo: .subheadline) private var wideThreshold: CGFloat = 260
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The card's measured width; until the first measurement the size class decides (regular cards are wide).
    @State private var measuredWidth: CGFloat?

    /// The play button's tap target: never under 44 pt, whatever the circle's size.
    private var playHit: CGFloat { max(playSize, 44) }
    private var isWide: Bool { measuredWidth.map { $0 >= wideThreshold } ?? (size == .regular) }
    /// Space between a superset bar's trailing edge and the names.
    private let supersetBarGap: CGFloat = 6
    private var titleFont: Font { .headline }

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
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                measuredWidth = $0
            }
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: template.id, in: namespace)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel(name: template.name))
        .accessibilityAddTraits(.isButton)
        .modifier(SpokenExercises(entries: summary.accessibilityEntries))
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
                .padding(.trailing, playSize + 12)
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
                        .font(.footnote)
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
                    lineRow(line)
                        .background(alignment: .leading) {
                            if let group = line.supersetGroup {
                                Capsule()
                                    .fill(Color.superset(group))
                                    .frame(width: Metrics.supersetBarWidth)
                                    .offset(x: -(Metrics.supersetBarWidth + supersetBarGap))
                            }
                        }
                }
                if let more = summary.overflowText {
                    Text(more)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
        }
    }

    /// The exercise's name; on a wide card its sets follow on the trailing edge of the same line and never truncate
    /// (the name gives way), and at accessibility sizes, where names wrap, they sit under the name.
    @ViewBuilder
    private func lineRow(_ line: TemplateCardSummary.Line) -> some View {
        let isAccessibility = dynamicTypeSize.isAccessibilitySize
        let name = Text(line.text)
            .lineLimit(isAccessibility ? nil : 1)
            .truncationMode(.tail)
        if isWide, let detail = line.detail {
            if isAccessibility {
                VStack(alignment: .leading, spacing: 0) {
                    name
                    Text(detail).monospacedDigit()
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    name
                    Spacer(minLength: 0)
                    Text(detail)
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
            }
        } else {
            name
        }
    }

    /// The recency ("Yesterday", "5 days ago"), in the primary colour so it does not read as another exercise, followed at
    /// a wide card by " · 52min" in secondary. A template never performed shows no footer, and an empty one shows its count ("No exercises") in secondary.
    @ViewBuilder
    private var meta: some View {
        if let last = summary.lastPerformed {
            let recency = Text(last).foregroundStyle(.primary)
            Group {
                if isWide, let duration = summary.lastDurationText {
                    recency + Text(" · \(duration)").foregroundStyle(.secondary)
                } else {
                    recency
                }
            }
            .font(.footnote)
            .multilineTextAlignment(.leading)
        } else if summary.lines.isEmpty {
            Text(summary.countText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
    }
}

/// The card's exercise lines for VoiceOver: the label stays short and each shown exercise (name, then its sets) is a
/// custom-content entry, read on demand from the rotor.
private struct SpokenExercises: ViewModifier {
    let entries: [TemplateCardSummary.AccessibilityEntry]

    func body(content: Content) -> some View {
        entries.reduce(AnyView(content)) { view, entry in
            AnyView(
                view.accessibilityCustomContent(
                    AccessibilityCustomContentKey(Text(verbatim: entry.label), id: entry.label),
                    entry.value
                )
            )
        }
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
