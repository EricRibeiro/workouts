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
    /// Fills the height of its grid row (content pinned to the top); false takes the natural height.
    var fillsRow = false
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
        .frame(maxHeight: fillsRow ? CGFloat.infinity : nil, alignment: .top)
        .dashboardCardStyle()
        .cardContentShape()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLoading ? "\(title), loading" : label)
        .accessibilityAddTraits(opens ? .isButton : [])
        .accessibilityIdentifier(identifier)
    }
}

/// The hero's headline: the done count as the big tinted figure (gray at zero), then "of 3 workouts" on the same baseline.
private struct WeekHeadline: View {
    let count: String
    let goalText: String
    let isDone: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize = 40

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(count)
                .font(.system(size: figureSize, weight: .semibold, design: .rounded))
                .foregroundStyle(isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .lineLimit(1)
            Text(goalText)
                .font(.body)
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

/// Volume and Time of the week in two columns, each over what is usual by now when there is a figure; stacked at
/// accessibility text sizes.
private struct WeekMetrics: View {
    let volume: String
    let duration: String
    let usualVolume: String?
    let usualDuration: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            metric("Volume", value: volume, usual: usualVolume)
            metric("Time", value: duration, usual: usualDuration)
        }
    }

    private func metric(_ title: String, value: String, usual: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            MetricText(value, style: .title2)
                .foregroundStyle(.primary)
            if let usual {
                Text("usually \(usual)")
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
    let part: DashboardCards.Part
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

/// The compact History page's cards: the This Week hero, and Recent PRs with Last Workout in even columns (the grid is as
/// wide as the list, so a wide closed layout may show two). Nothing is sized in points but the column minimum, which
/// scales with Dynamic Type. `DashboardColumns` composes the same cards for regular width.
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
    var part = Part.rest
    /// The records the regular-width layout lists, and so the most the history summary must carry.
    static let regularRecentPRLimit = 5
    /// How many Recent PRs the card lists.
    var recentPRLimit = 3
    let openWorkout: (UUID) -> Void
    var calendar: Calendar = .current
    var now: Date = .now

    /// The cards a `DashboardCards` draws: the This Week hero, or the others.
    enum Part {
        case hero, rest
    }

    /// The columns come from `EvenColumnGrid`: an even count from two up, so no card straddles the fold; the cards of a
    /// grid row share its height. The hero alone is one full-width card.
    @ViewBuilder
    var body: some View {
        switch part {
        case .hero:
            thisWeek
        case .rest:
            EvenColumnGrid(minimum: 250) {
                recents(fillsRow: true)
                lastWorkoutCard
            }
        }
    }

    @ViewBuilder
    private var lastWorkoutCard: some View {
        if let last = HistoryDashboard.lastWorkout(entries: entries) {
            lastWorkout(last, fillsRow: true)
        }
    }

    /// The hero card: the week's workouts against the goal, then its volume and time over what is usual by now.
    var thisWeek: some View {
        let week = HistoryDashboard.thisWeek(entries: entries, calendar: calendar, now: now)
        let toDate = HistoryDashboard.toDateBaseline(entries: entries, calendar: calendar, now: now)
        let text = HistoryDashboard.heroText(week: week, goal: goal, toDate: toDate)
        let calories = weekActiveKcal.map(FitnessFormat.kcalText)
        let calorieLabel = weekActiveKcal.map { ", \(FitnessFormat.wholeNumber($0)) active calories" } ?? ""
        let heartRate = weekAverageBpm.map(HistoryDashboard.heartRateText)
        let heartRateLabel = weekAverageBpm.map { ", \(HistoryDashboard.heartRateSpoken($0))" } ?? ""
        return DashboardCard(
            title: "This Week",
            isLoading: !isLoaded,
            label: text.spoken + calorieLabel + heartRateLabel,
            identifier: "history.card.thisWeek"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                WeekHeadline(count: text.countText, goalText: text.goalText, isDone: week.workouts > 0)
                GoalSegments(done: isLoaded ? week.workouts : 0, goal: goal)
                WeekMetrics(
                    volume: text.volumeText,
                    duration: text.durationText,
                    usualVolume: text.usualVolumeText,
                    usualDuration: text.usualDurationText
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

    func recents(fillsRow: Bool = false) -> some View {
        let shown = Array(recentPRs.prefix(recentPRLimit))
        let sentence =
            shown.isEmpty
            ? "Recent PRs, none yet"
            : "Recent PRs, " + shown.map(\.sentence).joined(separator: "; ")
        return DashboardCard(
            title: "Recent PRs",
            isLoading: !isLoaded,
            fillsRow: fillsRow,
            label: sentence,
            identifier: "history.card.recentPRs"
        ) {
            if !isLoaded {
                // Two placeholder rows in the shape of a record, so the card does not jump when the real ones arrive.
                ForEach(0..<2, id: \.self) { _ in
                    prRow(name: "Exercise name", text: "000 lb × 00")
                }
            } else if shown.isEmpty {
                Text("No records yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(shown) { pr in
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

    func lastWorkout(_ entry: HistoryEntry, fillsRow: Bool = false) -> some View {
        let date = HistoryList.dateText(entry.startedAt, now: now, calendar: calendar)
        let detail =
            "\(HistoryList.durationText(seconds: entry.durationSeconds)) · \(HistoryList.volumeText(entry.volume, unit: entry.unit))"
        return Button {
            openWorkout(entry.id)
        } label: {
            DashboardCard(
                title: "Last Workout",
                opens: true,
                fillsRow: fillsRow,
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
/// Workout. Every card takes its natural height and the columns are top-aligned, so a short card never carries a blank
/// band; Recent PRs lists up to five records here.
///
/// Half-open in book pose (an active, vertical division region inside this view) the left column ends at the division and
/// the right one starts after it, so the gutter is the fold itself; otherwise the gutter is the normal 12 pt. The same
/// views are laid out either way (a custom `Layout` changes only the widths), so folding does not rebuild the cards or the
/// chart. The horizontal fold (laptop pose) is not treated specially: the content scrolls through it.
struct DashboardColumns<Chart: View>: View {
    let entries: [HistoryEntry]
    let recentPRs: [RecentPR]
    /// Active calories this week from Apple Fitness; nil hides the figure.
    var weekActiveKcal: Double?
    /// Duration-weighted average heart rate this week from Apple Fitness; nil hides the figure.
    var weekAverageBpm: Double?
    /// False until the history summary has arrived (This Week and Recent PRs are placeholders until then).
    var isLoaded = true
    var calendar: Calendar = .current
    var now: Date = .now
    /// The weekly chart, under the hero.
    @ViewBuilder let chart: Chart
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
            recentPRLimit: DashboardCards.regularRecentPRLimit,
            openWorkout: openWorkout,
            calendar: calendar,
            now: now
        )
        FoldColumns {
            VStack(spacing: Metrics.dashboardSpacing) {
                cards.thisWeek
                chart
            }
            VStack(spacing: Metrics.dashboardSpacing) {
                cards.recents()
                if let last = HistoryDashboard.lastWorkout(entries: entries) {
                    cards.lastWorkout(last)
                }
            }
        }
    }
}

/// Two equal columns that keep off the vertical fold when the Duo is half-folded: both take the narrower half's width and the
/// gutter around the fold absorbs the rest (at least 12 pt); flat open or without a fold the gutter is the normal 12 pt. Takes exactly two child
/// views. Shared by the History dashboard and the workout detail.
struct FoldColumns<Left: View, Right: View>: View {
    let left: Left
    let right: Right

    /// The fold's horizontal extent in this view's own coordinate space, nil unless an active vertical division lies inside it.
    /// Flat open the hinge is inactive and the layout ignores it: equal columns, cards crossing the hinge, as Apple's Fitness does.
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
                divisions: proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame),
                width: proxy.size.width
            )
        } action: {
            division = $0
        }
    }
}

/// Two columns of equal width, top-aligned, each at its natural height. Without a division they split the width around a
/// 12 pt gutter; with one, each is as wide as the narrower side of it and the gutter between them contains it.
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
            proposal: ProposedViewSize(width: widths.left, height: nil)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + widths.left + widths.gap, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: widths.right, height: nil)
        )
    }
}
