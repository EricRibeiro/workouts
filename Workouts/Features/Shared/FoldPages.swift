//
//  FoldPages.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// Two pages side by side in their own vertical `ScrollView`s: `leading` content, and one `row` per item of `items` (then
/// `footer`). At regular width they are two equal columns across the full width (outer `margin`, `spacing` between), the
/// hinge ignored, as long as each column is at least `minimumColumn` wide; the Duo open flat therefore reads as one surface.
/// While the hinge is an active vertical division (the half-folded book pose) the pages instead anchor on it: the leading
/// page runs to the division, the trailing page starts after it (`FoldPlacement.pageFrames`). Otherwise (compact width, a
/// narrow container) both pages stack in one `ScrollView`. The two column cases are the same view tree, so folding the Duo
/// keeps each page's scroll position; the stacked case is another tree, so the reader's place crosses the switch by hand:
/// each tree's `ScrollPosition` is read into `savedID` only when a user scroll comes to rest (layout during the switch never
/// overwrites it), and the new tree's scroll view is sent there with an explicit `scrollTo` once it has appeared.
struct FoldPages<Leading: View, Item: Identifiable, Row: View, Footer: View>: View {
    var margin: CGFloat = 16
    var spacing: CGFloat = 20
    let items: [Item]
    @ViewBuilder let leading: Leading
    @ViewBuilder let row: (Item) -> Row
    @ViewBuilder let footer: Footer

    init(
        margin: CGFloat = 16,
        spacing: CGFloat = 20,
        items: [Item],
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder row: @escaping (Item) -> Row,
        @ViewBuilder footer: () -> Footer
    ) {
        self.margin = margin
        self.spacing = spacing
        self.items = items
        self.leading = leading()
        self.row = row
        self.footer = footer()
    }

    /// The narrowest a page may get before the pages stack instead.
    static var minimumColumn: CGFloat { 320 }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The pages' frames in this view's own coordinate space, nil when the pages stack.
    @State private var frames: FoldPlacement.PageFrames?
    /// The reader's place: the item at the top when the last user scroll ended, nil while still in the leading content.
    @State private var savedID: Item.ID?
    @State private var stackedPosition = ScrollPosition(idType: Item.ID.self)
    @State private var trailingPosition = ScrollPosition(idType: Item.ID.self)

    private var showsPages: Bool { horizontalSizeClass == .regular && frames != nil }

    var body: some View {
        Group {
            if showsPages, let frames {
                ZStack(alignment: .topLeading) {
                    page(leading, frame: frames.leading)
                    page(trailing, frame: frames.trailing)
                        .scrollPosition($trailingPosition, anchor: .top)
                        .onScrollPhaseChange { old, new in
                            if Self.userScrollEnded(old, new) { record(trailingPosition.viewID(type: Item.ID.self)) }
                        }
                        .onAppear { restore(pages: true) }
                        .onDisappear { trailingPosition = ScrollPosition(idType: Item.ID.self) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: spacing) {
                        leading
                        trailing
                    }
                    .padding(.horizontal, margin)
                    .padding(.bottom)
                }
                .scrollPosition($stackedPosition, anchor: .top)
                .onScrollPhaseChange { old, new in
                    // The first item sits under the leading content: while it is the top-most one, the reader is still at the top.
                    guard Self.userScrollEnded(old, new) else { return }
                    let id = stackedPosition.viewID(type: Item.ID.self)
                    record(id == items.first?.id ? nil : id)
                }
                .onAppear { restore(pages: false) }
                .onDisappear { stackedPosition = ScrollPosition(idType: Item.ID.self) }
            }
        }
        // Measured on a background view: on the page container itself the division is not reported.
        .background {
            Color.clear
                .onGeometryChange(for: FoldPlacement.PageFrames?.self) { proxy in
                    let width = proxy.size.width
                    let division = FoldPlacement.columnGap(
                        divisions: proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame),
                        width: width
                    )
                    if division != nil {
                        return FoldPlacement.pageFrames(total: width, division: division, margin: margin)
                    }
                    return FoldPlacement.equalPageFrames(
                        total: width,
                        margin: margin,
                        spacing: spacing,
                        minimumPage: Self.minimumColumn
                    )
                } action: {
                    frames = $0
                }
        }
    }

    /// The items' stack, the scroll target layout of whichever scroll view holds it.
    private var trailing: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(items) { item in
                row(item)
            }
            footer
        }
        .scrollTargetLayout()
    }

    /// A scroll view also goes idle while it is torn down or rebuilt; only a rest after the reader's own scroll counts.
    private static func userScrollEnded(_ old: ScrollPhase, _ new: ScrollPhase) -> Bool {
        new == .idle && (old == .interacting || old == .decelerating)
    }

    private func record(_ id: Item.ID?) {
        savedID = id
    }

    /// Sends a freshly built scroll view to the saved place, after its first layout pass.
    private func restore(pages: Bool) {
        let id = savedID
        Task { @MainActor in
            await Task.yield()
            if pages {
                if let id {
                    trailingPosition.scrollTo(id: id, anchor: .top)
                } else {
                    trailingPosition.scrollTo(edge: .top)
                }
            } else {
                if let id {
                    stackedPosition.scrollTo(id: id, anchor: .top)
                } else {
                    stackedPosition.scrollTo(edge: .top)
                }
            }
        }
    }

    private func page(_ content: some View, frame: FoldPlacement.PageFrame) -> some View {
        ScrollView {
            content.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom)
        }
        .frame(width: frame.width)
        .offset(x: frame.x)
    }
}

extension FoldPages where Footer == EmptyView {
    init(
        margin: CGFloat = 16,
        spacing: CGFloat = 20,
        items: [Item],
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder row: @escaping (Item) -> Row
    ) {
        self.init(margin: margin, spacing: spacing, items: items, leading: leading, row: row) { EmptyView() }
    }
}

#if DEBUG
    /// One numbered coloured card, so a page's width, scroll and edges show in every Duo pose.
    private struct FoldPagesCard: View {
        let number: Int
        let hue: Double

        var body: some View {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hue: hue, saturation: 0.55, brightness: 0.7))
                .frame(height: 120)
                .overlay {
                    Text("\(number)")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Card \(number)")
        }
    }

    private struct FoldPagesNumber: Identifiable {
        let id: Int
    }

    /// Two tall stacks on the container, for the gallery (`-preview FoldPages`) and the preview: 6 leading cards, 14 trailing.
    struct FoldPagesDemo: View {
        var body: some View {
            FoldPages(items: (1...14).map(FoldPagesNumber.init)) {
                VStack(spacing: 20) {
                    // String ids: an Int id here would share a scroll target id with the item of that number.
                    ForEach(1...6, id: \.description) { FoldPagesCard(number: $0, hue: 0.1) }
                }
            } row: { item in
                FoldPagesCard(number: item.id, hue: 0.6)
            }
        }
    }

    #Preview("Fold pages") {
        FoldPagesDemo()
    }
#endif
