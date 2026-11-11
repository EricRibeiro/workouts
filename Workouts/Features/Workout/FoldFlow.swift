//
//  FoldFlow.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The Workout tab's sections in one container at every width, so folding or unfolding the Duo moves the sections instead of
/// rebuilding them (a section's grid width, an open menu and a zoom source survive). At compact width it is one full-width
/// column; at regular width (the closed Duo's width versus the open one) two fold-aware columns. Sections take the columns in
/// order, first left, second right, third left again, so the reading and VoiceOver order stay the section order. Each column
/// is a top-aligned stack, so a tall section does not stretch its neighbour. A single section keeps the full width, its own
/// grid placing cards around the fold. The placement itself is `FoldPlacement.sectionFrames`.
struct FoldFlow<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder let content: Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The fold's horizontal extent in this view's own coordinate space, nil unless a vertical division lies inside it.
    /// Inactive regions count, so the gutter already sits on the hinge when the Duo is open flat.
    @State private var division: ClosedRange<CGFloat>?

    var body: some View {
        FoldFlowLayout(columns: horizontalSizeClass == .regular ? 2 : 1, division: division, rowSpacing: spacing) {
            content
        }
        .onGeometryChange(for: ClosedRange<CGFloat>?.self) { proxy in
            FoldPlacement.columnGap(
                divisions: proxy.reservedRegions(kind: .division, options: .includeInactive).map(\.frame),
                width: proxy.size.width
            )
        } action: {
            division = $0
        }
    }
}

/// One or two columns (two of equal width, the narrower half's, around the fold; see `FoldPlacement.columnWidths`) that take
/// the subviews alternately, each at its natural height from the top. The arithmetic is `FoldPlacement.sectionFrames`.
private struct FoldFlowLayout: Layout {
    var columns: Int
    var division: ClosedRange<CGFloat>?
    var rowSpacing: CGFloat
    var columnSpacing: CGFloat = 12

    private func placement(total: CGFloat, subviews: Subviews) -> FoldPlacement.SectionLayout {
        FoldPlacement.sectionFrames(
            count: subviews.count,
            total: total,
            division: division,
            columns: columns,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing,
            height: { index, width in
                subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            }
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 0
        return CGSize(width: total, height: placement(total: total, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = placement(total: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, layout.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.x, y: bounds.minY + frame.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: nil)
            )
        }
    }
}
