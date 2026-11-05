//
//  DashboardCards.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The Fitness card shape shared by the History dashboard: a rounded `secondarySystemBackground` fill, no border,
/// 20 pt corners. `WeeklyGoalChart` wears the same container.
extension View {
    func dashboardCardStyle() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

/// A dashboard card: a tinted title row (symbol, title, a trailing chevron when the card opens something) over its
/// content. One accessibility element: the caller supplies the sentence and the identifier.
struct DashboardCard<Content: View>: View {
    let title: String
    let systemImage: String
    var opens = false
    let label: String
    let identifier: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer(minLength: 4)
                if opens {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            content
        }
        // Cards in one grid row share the tallest card's height; content stays pinned to the top.
        .frame(maxHeight: .infinity, alignment: .top)
        .dashboardCardStyle()
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(opens ? .isButton : [])
        .accessibilityIdentifier(identifier)
    }
}

/// The big tinted figure of a card.
private struct CardValue: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.tint)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }
}

/// `DashboardCards` with the weekly goal read from Settings (the same clamp as the chart).
struct DashboardSection: View {
    let entries: [HistoryEntry]
    let recentPRs: [RecentPR]
    /// Active calories this week from Apple Fitness; nil hides the figure.
    var weekActiveKcal: Double?
    /// Duration-weighted average heart rate this week from Apple Fitness; nil hides the figure.
    var weekAverageBpm: Double?
    let openWorkout: (UUID) -> Void

    @AppStorage(SettingsKey.weeklyGoal.rawValue) private var storedGoal = SettingsStore.weeklyGoalDefault

    var body: some View {
        DashboardCards(
            entries: entries,
            recentPRs: recentPRs,
            goal: min(max(storedGoal, 1), 14),
            weekActiveKcal: weekActiveKcal,
            weekAverageBpm: weekAverageBpm,
            openWorkout: openWorkout
        )
    }
}

/// This Week, Recent PRs and Last Workout in even columns: the grid is as wide as the list, so the closed Duo shows
/// one column and the open wide display two or three. Nothing is sized in points but the column minimum, which scales
/// with Dynamic Type.
struct DashboardCards: View {
    let entries: [HistoryEntry]
    let recentPRs: [RecentPR]
    let goal: Int
    /// Active calories this week from Apple Fitness; nil hides the figure.
    var weekActiveKcal: Double?
    /// Duration-weighted average heart rate this week from Apple Fitness; nil hides the figure.
    var weekAverageBpm: Double?
    let openWorkout: (UUID) -> Void
    var calendar: Calendar = .current
    var now: Date = .now

    /// The columns come from `EvenColumnGrid`: an even count from two up, so no card straddles the fold.
    var body: some View {
        EvenColumnGrid(minimum: 250) {
            thisWeek
            recents
            if let last = HistoryDashboard.lastWorkout(entries: entries) {
                lastWorkout(last)
            }
        }
    }

    var thisWeek: some View {
        let week = HistoryDashboard.thisWeek(entries: entries, calendar: calendar, now: now)
        let duration = HistoryList.durationText(seconds: week.durationSeconds)
        let volume = HistoryList.volumeText(week.volume, unit: week.unit)
        let calories = weekActiveKcal.map(FitnessFormat.kcalText)
        let calorieLabel = weekActiveKcal.map { ", \(FitnessFormat.wholeNumber($0)) active calories" } ?? ""
        let heartRate = weekAverageBpm.map(HistoryDashboard.heartRateText)
        let heartRateLabel = weekAverageBpm.map { ", \(HistoryDashboard.heartRateSpoken($0))" } ?? ""
        return DashboardCard(
            title: "This Week",
            systemImage: "calendar",
            label:
                "This week, \(week.workouts) of \(goal) workouts, \(duration), \(volume)\(calorieLabel)\(heartRateLabel)",
            identifier: "history.card.thisWeek"
        ) {
            CardValue(text: "\(week.workouts) / \(goal)")
            Text("workouts this week")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(duration) · \(volume)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let calories {
                Label(calories + " active", systemImage: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let heartRate {
                Label(heartRate + " avg", systemImage: "heart.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var recents: some View {
        let sentence =
            recentPRs.isEmpty
            ? "Recent PRs, none yet"
            : "Recent PRs, " + recentPRs.map(\.sentence).joined(separator: "; ")
        return DashboardCard(
            title: "Recent PRs",
            systemImage: "medal.fill",
            label: sentence,
            identifier: "history.card.recentPRs"
        ) {
            if recentPRs.isEmpty {
                Text("No records yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recentPRs) { pr in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "trophy.fill")
                                .font(.subheadline)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(pr.exerciseName)
                                    .font(.subheadline.weight(.semibold))
                                Text(pr.text)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    func lastWorkout(_ entry: HistoryEntry) -> some View {
        let date = HistoryList.dateText(entry.startedAt, now: now, calendar: calendar)
        let detail =
            "\(HistoryList.durationText(seconds: entry.durationSeconds)) · \(HistoryList.volumeText(entry.volume, unit: entry.unit))"
        return Button {
            openWorkout(entry.id)
        } label: {
            DashboardCard(
                title: "Last Workout",
                systemImage: "figure.strengthtraining.traditional",
                opens: true,
                label: "Last workout, \(entry.name), \(date), \(detail)",
                identifier: "history.card.lastWorkout"
            ) {
                Text(entry.name)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(2)
                Text(date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The regular-width dashboard: the weekly chart and the three cards in exactly two columns, so nothing is wider than half
/// the display and nothing crosses the fold. Left: the chart, then Last Workout. Right: This Week, then Recent PRs. That
/// pairing makes the columns near-equal in height (the chart is the tallest card, Last Workout the shortest), and each
/// column's last card stretches so the bottoms line up.
///
/// Half-open in book pose (an active, vertical division region inside this view) the left column ends at the division and
/// the right one starts after it, so the gutter is the fold itself; otherwise the gutter is the normal 12 pt. The same
/// views are laid out either way (a custom `Layout` changes only the widths), so folding does not rebuild the cards or the
/// chart. The horizontal fold (laptop pose) is not treated specially: the content scrolls through it.
struct DashboardColumns: View {
    /// Start dates of the finished workouts (the chart).
    let starts: [Date]
    let entries: [HistoryEntry]
    let recentPRs: [RecentPR]
    /// Active calories this week from Apple Fitness; nil hides the figure.
    var weekActiveKcal: Double?
    /// Duration-weighted average heart rate this week from Apple Fitness; nil hides the figure.
    var weekAverageBpm: Double?
    let openWorkout: (UUID) -> Void

    @AppStorage(SettingsKey.weeklyGoal.rawValue) private var storedGoal = SettingsStore.weeklyGoalDefault
    /// The division's horizontal extent in this view's own coordinate space, nil unless it is active, vertical and inside.
    @State private var division: ClosedRange<CGFloat>?

    var body: some View {
        let cards = DashboardCards(
            entries: entries,
            recentPRs: recentPRs,
            goal: min(max(storedGoal, 1), 14),
            weekActiveKcal: weekActiveKcal,
            weekAverageBpm: weekAverageBpm,
            openWorkout: openWorkout
        )
        TwoColumnLayout(division: division) {
            VStack(spacing: 12) {
                WeeklyGoalSection(starts: starts)
                if let last = HistoryDashboard.lastWorkout(entries: entries) {
                    cards.lastWorkout(last)
                }
            }
            VStack(spacing: 12) {
                cards.thisWeek
                cards.recents
            }
        }
        .onGeometryChange(for: ClosedRange<CGFloat>?.self) { proxy in
            FoldPlacement.columnGap(
                divisions: proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame),
                width: proxy.size.width
            )
        } action: {
            division = $0
        }
    }
}

/// Two columns of equal height. Without a division they split the width around a 12 pt gutter; with one, the left column
/// is everything before it and the right everything after it. Both children are proposed the full row height so a
/// column's flexible last card can stretch to the other column's bottom.
private struct TwoColumnLayout: Layout {
    var division: ClosedRange<CGFloat>?
    var spacing: CGFloat = 12

    /// Left width, gutter width, right width for a total width.
    private func split(_ total: CGFloat) -> (left: CGFloat, gap: CGFloat, right: CGFloat) {
        FoldPlacement.columnWidths(total: total, division: division, spacing: spacing)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let total =
            proposal.width
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(spacing, +)
        let widths = split(total)
        let left = subviews[0].sizeThatFits(ProposedViewSize(width: widths.left, height: nil))
        let right = subviews[1].sizeThatFits(ProposedViewSize(width: widths.right, height: nil))
        return CGSize(width: total, height: max(left.height, right.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let widths = split(bounds.width)
        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: widths.left, height: bounds.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + widths.left + widths.gap, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: widths.right, height: bounds.height)
        )
    }
}
