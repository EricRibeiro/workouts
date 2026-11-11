//
//  Metrics.swift
//  Workouts
//

import SwiftUI

/// Shared geometry tokens: one number per repeated shape, so two screens showing the same object cannot drift.
enum Metrics {
    /// Corner radius of every grouped card (dashboard, template, exercise detail, media), drawn `.continuous`.
    static let cardCornerRadius: CGFloat = 20
    /// Inner padding of a dashboard-style card (`.padding()`'s default, named so the About/Records cards share it).
    static let cardPadding: CGFloat = 16
    /// Leading and trailing margin of a screen's content: the large title's and a `List` row's inset, so a `ScrollView`
    /// screen's headers and cards start on the title's edge as History's do.
    static let contentMargin: CGFloat = 20
    /// Vertical padding of a card that wraps rows which already carry their own height (exercise detail lists).
    static let cardRowsVerticalPadding: CGFloat = 6
    /// Gap between the History dashboard's cards: in a grid row, in a column, and between the chart and the cards under it.
    static let dashboardSpacing: CGFloat = 12
    /// Width of the superset bar on a template card, template preview, set table and History detail.
    static let supersetBarWidth: CGFloat = 4
    /// Text indent that clears the superset bar on a template card or preview line.
    static let supersetBarIndent: CGFloat = 9
    /// Base width of the set-label column (1, 2, W, F…) in every set list; each view scales it with `@ScaledMetric(relativeTo: .body)`
    /// so the "175 kg × 5" text starts at the same x in every row and on every screen.
    static let setLabelWidth: CGFloat = 28
}

extension View {
    /// The title of a section over a grid of cards: a Workout tab folder and a History month look alike.
    func sectionTitleStyle() -> some View {
        font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
    }

    /// The box around a `sectionTitleStyle()` title: at least 44 pt tall with the text at its bottom, and 8 pt between
    /// the title and the cards under it, so it reads as that section's header rather than floating between two.
    func sectionHeaderBox() -> some View {
        frame(maxWidth: .infinity, minHeight: 44, alignment: .bottomLeading)
            .padding(.bottom, 8)
    }

    /// The card background shared by every grouped surface: `secondarySystemBackground`, continuous 20 pt corners.
    func cardBackground() -> some View {
        background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
        )
    }

    /// Hit-testing shape matching `cardBackground()`.
    func cardContentShape() -> some View {
        contentShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous))
    }
}
