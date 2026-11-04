//
//  TemplateCard.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// A folder's templates as Fitness-shaped cards in even columns (task 3.2a). The columns come from the grid's own width
/// (`EvenColumnGrid`), so on the open Duo the gutter falls on the fold; at the closed Duo's width it is two.
struct TemplateGrid: View {
    let templates: [Template]
    let finishedWorkouts: [Workout]
    let namespace: Namespace.ID
    let open: (Template) -> Void

    var body: some View {
        EvenColumnGrid(minimum: 160) {
            ForEach(templates) { template in
                TemplateCard(
                    template: template,
                    summary: TemplateCardSummary.make(for: template, finishedWorkouts: finishedWorkouts),
                    namespace: namespace,
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
    let open: () -> Void

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
                                .lineLimit(1)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel(name: template.name))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("workout.template.\(template.id.uuidString)")
    }
}
