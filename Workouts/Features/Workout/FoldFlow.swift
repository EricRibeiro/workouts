//
//  FoldFlow.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The Workout tab's sections: one column at compact width, two fold-aware columns at regular width (the closed Duo's
/// width versus the open one). Sections take the columns in order, first left, second right, third left again, so the
/// reading and VoiceOver order stay the section order. Each column is a top-aligned stack, so a tall section does not
/// stretch its neighbour. A single section keeps the full width, its own grid placing cards around the fold.
struct FoldFlow<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder let content: Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The fold's horizontal extent in this view's own coordinate space, nil unless a vertical division lies inside it.
    /// Inactive regions count, so the gutter already sits on the hinge when the Duo is open flat.
    @State private var division: ClosedRange<CGFloat>?

    var body: some View {
        if horizontalSizeClass == .regular {
            FoldFlowLayout(division: division, rowSpacing: spacing) {
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
        } else {
            LazyVStack(alignment: .leading, spacing: spacing) {
                content
            }
        }
    }
}

/// Two columns of equal width (the narrower half's, around the fold; see `FoldPlacement.columnWidths`) that take the
/// subviews alternately, each at its natural height from the top.
private struct FoldFlowLayout: Layout {
    var division: ClosedRange<CGFloat>?
    var rowSpacing: CGFloat
    var columnSpacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 0
        if subviews.count == 1 {
            let height = subviews[0].sizeThatFits(ProposedViewSize(width: total, height: nil)).height
            return CGSize(width: total, height: height)
        }
        let widths = FoldPlacement.columnWidths(total: total, division: division, spacing: columnSpacing)
        var heights: [CGFloat] = [0, 0]
        for (index, subview) in subviews.enumerated() {
            let column = index % 2
            let height = subview.sizeThatFits(
                ProposedViewSize(width: column == 0 ? widths.left : widths.right, height: nil)
            )
            .height
            heights[column] += (heights[column] > 0 ? rowSpacing : 0) + height
        }
        return CGSize(width: total, height: max(heights[0], heights[1]))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if subviews.count == 1 {
            subviews[0].place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
            return
        }
        let widths = FoldPlacement.columnWidths(total: bounds.width, division: division, spacing: columnSpacing)
        let rightX = bounds.minX + widths.left + widths.gap
        var bottoms: [CGFloat] = [bounds.minY, bounds.minY]
        var placed = [false, false]
        for (index, subview) in subviews.enumerated() {
            let column = index % 2
            let width = column == 0 ? widths.left : widths.right
            let proposed = ProposedViewSize(width: width, height: nil)
            let height = subview.sizeThatFits(proposed).height
            let y = bottoms[column] + (placed[column] ? rowSpacing : 0)
            subview.place(
                at: CGPoint(x: column == 0 ? bounds.minX : rightX, y: y),
                anchor: .topLeading,
                proposal: proposed
            )
            bottoms[column] = y + height
            placed[column] = true
        }
    }
}
