//
//  EvenColumnGrid.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// A `LazyVGrid` whose column count comes from its own width, never from a size class or a device check: as many columns
/// as fit at the Dynamic-Type-scaled `minimum`, forced even from two up so the gutter falls on the fold and no card
/// straddles it (`docs/port/duo-layout.md`, Grids). When the fold lies inside the grid (the bar strip shifts the grid off
/// the display's centre) the middle gutter is the fold itself (`FoldPlacement.foldColumns`). One column when not even two fit (large accessibility sizes).
/// Shared by the History dashboard and the Workout tab's template grid.
struct EvenColumnGrid<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    @ScaledMetric private var minimum: CGFloat
    @State private var width: CGFloat = 0
    /// The fold's horizontal extent in this grid's own coordinate space, nil unless a vertical division lies inside it.
    /// Inactive regions count, so the gutter already sits on the hinge when the Duo is open flat.
    @State private var division: ClosedRange<CGFloat>?

    /// `minimum` is the narrowest a column may be at the default text size; it scales with Dynamic Type.
    init(minimum: CGFloat, spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        _minimum = ScaledMetric(wrappedValue: minimum, relativeTo: .body)
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            content
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
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

    /// Columns split around the fold when it lies inside the grid, else an even count by width.
    private var columns: [GridItem] {
        if let folded = FoldPlacement.foldColumns(
            width: width,
            minimum: minimum,
            spacing: spacing,
            division: division
        ) {
            return folded.map { GridItem(.fixed($0.width), spacing: $0.spacingAfter, alignment: .top) }
        }
        return Array(
            repeating: GridItem(.flexible(), spacing: spacing, alignment: .top),
            count: Self.columnCount(width: width, minimum: minimum, spacing: spacing)
        )
    }

    /// Columns that fit `width` at `minimum`; an even number from two up (three becomes two, five four), else one.
    static func columnCount(width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        let fit = max(1, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
        return fit >= 3 && fit.isMultiple(of: 2) == false ? fit - 1 : fit
    }
}
