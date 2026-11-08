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
    /// Vertical padding of a card that wraps rows which already carry their own height (exercise detail lists).
    static let cardRowsVerticalPadding: CGFloat = 6
    /// Gap between the History dashboard's cards: in a grid row, in a column, and between the chart and the cards under it.
    static let dashboardSpacing: CGFloat = 12
    /// Width of the superset bar on a template card, template preview, set table and History detail.
    static let supersetBarWidth: CGFloat = 4
    /// Text indent that clears the superset bar on a template card or preview line.
    static let supersetBarIndent: CGFloat = 9
    /// Corner radius of a sticky note, in the exercise detail and under a set row.
    static let stickyNoteCornerRadius: CGFloat = 10
}

extension View {
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
