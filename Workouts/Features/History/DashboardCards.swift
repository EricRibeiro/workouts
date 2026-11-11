//
//  DashboardCards.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The Fitness card shape shared by the History dashboard: a rounded `secondarySystemBackground` fill, no border,
/// continuous 20 pt corners (`Metrics.cardCornerRadius`). `WeeklyGoalChart` wears the same container.
extension View {
    func dashboardCardStyle() -> some View {
        padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
    }
}

/// A dashboard card: a title row (title, a trailing chevron when the card opens something) over its
/// content. One accessibility element: the caller supplies the sentence and the identifier.
struct DashboardCard<Content: View>: View {
    let title: String
    var opens = false
    /// The summary has not arrived: the content is drawn as placeholder blocks and the sentence says so, instead of
    /// presenting an empty result as fact.
    var isLoading = false
    let label: String
    let identifier: String
    @ViewBuilder let content: Content
    @ScaledMetric(relativeTo: .caption2) private var chevronSize = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                if opens {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: chevronSize, height: chevronSize)
                        .background(Circle().fill(.fill.tertiary))
                }
            }
            content
                .redacted(reason: isLoading ? .placeholder : [])
        }
        // Cards in one grid row share the tallest card's height; content stays pinned to the top.
        .frame(maxHeight: .infinity, alignment: .top)
        .dashboardCardStyle()
        .cardContentShape()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLoading ? "\(title), loading" : label)
        .accessibilityAddTraits(opens ? .isButton : [])
        .accessibilityIdentifier(identifier)
    }
}

/// The hero's headline: the done count as the big tinted figure, then "of 3 workouts" on the same baseline.
private struct WeekHeadline: View {
    let done: Int
    let goal: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            MetricText("\(done)", style: .largeTitle)
                .foregroundStyle(.tint)
                .lineLimit(1)
            Text("of \(goal) \(goal == 1 ? "workout" : "workouts")")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

/// One capsule per goal workout, equal widths across the card: tinted for a done one, quiet for the rest. Decorative; the
/// card's sentence carries the count.
private struct GoalSegments: View {
    let done: Int
    let goal: Int
    @ScaledMetric(relativeTo: .caption) private var height = 6

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<goal, id: \.self) { index in
                Capsule()
                    .fill(index < done ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary))
                    .frame(height: height)
            }
        }
        .animation(.snappy, value: done)
        .accessibilityHidden(true)
    }
}

/// Volume and Time of the week in two columns, each over its four-week average when there is one; stacked at
/// accessibility text sizes.
private struct WeekMetrics: View {
    let volume: String
    let duration: String
    let averageVolume: String?
    let averageDuration: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            metric("Volume", value: volume, average: averageVolume)
            metric("Time", value: duration, average: averageDuration)
        }
    }

    private func metric(_ title: String, value: String, average: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            MetricText(value, style: .title2)
                .foregroundStyle(.primary)
            if let average {
                Text("avg \(average)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    /// False until the history summary has arrived (This Week and Recent PRs are placeholders until then).
    var isLoaded = true
    /// Which cards to draw: the compact History page puts the weekly chart between the hero and the rest.
    var part = DashboardCards.Part.all
    let openWorkout: (UUID) -> Void

    @AppStorage(SettingsKey.weeklyGoal.rawValue) private var storedGoal = SettingsStore.weeklyGoalDefault

    var body: some View {
        DashboardCards(
            entries: entries,
            recentPRs: recentPRs,
            goal: min(max(storedGoal, 1), 14),
            weekActiveKcal: weekActiveKcal,
            weekAverageBpm: weekAverageBpm,
            isLoaded: isLoaded,
            part: part,
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
    /// False until the history summary has arrived: This Week and Recent PRs are drawn as placeholders.
    var isLoaded = true
    var part = Part.all
    let openWorkout: (UUID) -> Void
    var calendar: Calendar = .current
    var now: Date = .now

    /// The cards a `DashboardCards` draws: the This Week hero, the others, or all three in one grid.
    enum Part {
        case all, hero, rest
    }

    /// The columns come from `EvenColumnGrid`: an even count from two up, so no card straddles the fold. The hero alone is
    /// one full-width card.
    @ViewBuilder
    var body: some View {
        switch part {
        case .hero:
            thisWeek
        case .rest:
            EvenColumnGrid(minimum: 250) {
                recents
                lastWorkoutCard
            }
        case .all:
            EvenColumnGrid(minimum: 250) {
                thisWeek
                recents
                lastWorkoutCard
            }
        }
    }

    @ViewBuilder
    private var lastWorkoutCard: some View {
        if let last = HistoryDashboard.lastWorkout(entries: entries) {
            lastWorkout(last)
        }
    }

    /// The hero card: the week's workouts against the goal, then its volume and time over the four-week average.
    var thisWeek: some View {
        let week = HistoryDashboard.thisWeek(entries: entries, calendar: calendar, now: now)
        // The current week and the four before it, so the baseline has its window.
        let totals = HistoryDashboard.weeklyTotals(entries: entries, weeks: 5, calendar: calendar, now: now)
        let baseline = HistoryDashboard.baseline(totals: totals)
        let duration = week.workouts == 0 ? "0min" : HistoryList.durationText(seconds: week.durationSeconds)
        let volume = HistoryList.volumeText(week.volume, unit: week.unit)
        let averageVolume = baseline.map { HistoryList.volumeText($0.volume.rounded(), unit: week.unit) }
        let averageDuration = baseline.map { HistoryList.durationText(seconds: $0.durationSeconds) }
        let detail = Self.weekDetail(week: week, duration: duration, volume: volume)
        let detailLabel = detail.map { ", \($0.replacingOccurrences(of: " · ", with: ", "))" } ?? ""
        let baselineLabel =
            baseline.map {
                ", 4-week average \(HistoryList.volumeText($0.volume.rounded(), unit: week.unit)), "
                    + FitnessFormat.spokenDuration(seconds: TimeInterval($0.durationSeconds))
            } ?? ""
        let calories = weekActiveKcal.map(FitnessFormat.kcalText)
        let calorieLabel = weekActiveKcal.map { ", \(FitnessFormat.wholeNumber($0)) active calories" } ?? ""
        let heartRate = weekAverageBpm.map(HistoryDashboard.heartRateText)
        let heartRateLabel = weekAverageBpm.map { ", \(HistoryDashboard.heartRateSpoken($0))" } ?? ""
        return DashboardCard(
            title: "This Week",
            isLoading: !isLoaded,
            label:
                "This week, \(week.workouts) of \(goal) \(goal == 1 ? "workout" : "workouts")\(detailLabel)\(baselineLabel)\(calorieLabel)\(heartRateLabel)",
            identifier: "history.card.thisWeek"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                WeekHeadline(done: week.workouts, goal: goal)
                GoalSegments(done: isLoaded ? week.workouts : 0, goal: goal)
                WeekMetrics(
                    volume: volume,
                    duration: duration,
                    averageVolume: averageVolume,
                    averageDuration: averageDuration
                )
            }
            if let calories {
                Label(calories + " active", systemImage: "flame.fill")
                    .labelStyle(.fixedIcon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let heartRate {
                Label(heartRate + " avg", systemImage: "heart.fill")
                    .labelStyle(.fixedIcon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// `duration · volume`; nothing for a week with no workouts, and the duration alone when nothing was lifted.
    private static func weekDetail(week: ThisWeekSummary, duration: String, volume: String) -> String? {
        guard week.workouts > 0 else { return nil }
        return week.volume > 0 ? "\(duration) · \(volume)" : duration
    }

    var recents: some View {
        let sentence =
            recentPRs.isEmpty
            ? "Recent PRs, none yet"
            : "Recent PRs, " + recentPRs.map(\.sentence).joined(separator: "; ")
        return DashboardCard(
            title: "Recent PRs",
            isLoading: !isLoaded,
            label: sentence,
            identifier: "history.card.recentPRs"
        ) {
            if !isLoaded {
                // Two placeholder rows in the shape of a record, so the card does not jump when the real ones arrive.
                ForEach(0..<2, id: \.self) { _ in
                    prRow(name: "Exercise name", text: "000 lb × 00")
                }
            } else if recentPRs.isEmpty {
                Text("No records yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recentPRs) { pr in
                        prRow(name: pr.exerciseName, text: pr.text)
                    }
                }
            }
        }
    }

    private func prRow(name: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.subheadline)
                .foregroundStyle(Color.record)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                opens: true,
                label: "Last workout, \(entry.name), \(date), \(detail)",
                identifier: "history.card.lastWorkout"
            ) {
                Text(entry.name)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
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
/// the display and nothing crosses the fold. Left: the This Week hero, then the chart. Right: Recent PRs, then Last
/// Workout. The hero and the chart are the tall cards, so the columns come out near-equal in height, and each column's
/// last card stretches so the bottoms line up.
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
    /// False until the history summary has arrived (This Week and Recent PRs are placeholders until then).
    var isLoaded = true
    let openWorkout: (UUID) -> Void

    @AppStorage(SettingsKey.weeklyGoal.rawValue) private var storedGoal = SettingsStore.weeklyGoalDefault

    var body: some View {
        let cards = DashboardCards(
            entries: entries,
            recentPRs: recentPRs,
            goal: min(max(storedGoal, 1), 14),
            weekActiveKcal: weekActiveKcal,
            weekAverageBpm: weekAverageBpm,
            isLoaded: isLoaded,
            openWorkout: openWorkout
        )
        FoldColumns {
            VStack(spacing: Metrics.dashboardSpacing) {
                cards.thisWeek
                WeeklyGoalSection(starts: starts, entries: entries)
            }
            VStack(spacing: Metrics.dashboardSpacing) {
                cards.recents
                if let last = HistoryDashboard.lastWorkout(entries: entries) {
                    cards.lastWorkout(last)
                }
            }
        }
    }
}

/// Two equal columns that keep off the vertical fold (half-open or flat open): both take the narrower half's width and the
/// gutter around the fold absorbs the rest (at least 12 pt); without a fold the gutter is the normal 12 pt. Takes exactly two child
/// views. Shared by the History dashboard and the workout detail.
struct FoldColumns<Left: View, Right: View>: View {
    let left: Left
    let right: Right

    /// The fold's horizontal extent in this view's own coordinate space, nil unless a vertical division lies inside it.
    /// Inactive regions count, so the gutter already sits on the hinge when the Duo is open flat.
    @State private var division: ClosedRange<CGFloat>?

    init(@ViewBuilder content: () -> TupleView<(Left, Right)>) {
        (left, right) = content().value
    }

    var body: some View {
        TwoColumnLayout(division: division) {
            left
            right
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

/// Two columns of equal width and height. Without a division they split the width around a 12 pt gutter; with one, each is
/// as wide as the narrower side of it and the gutter between them contains it. Both children are proposed the full row height so a
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
