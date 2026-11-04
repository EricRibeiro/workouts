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
    let openWorkout: (UUID) -> Void

    @AppStorage(SettingsKey.weeklyGoal.rawValue) private var storedGoal = SettingsStore.weeklyGoalDefault

    var body: some View {
        DashboardCards(
            entries: entries,
            recentPRs: recentPRs,
            goal: min(max(storedGoal, 1), 14),
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
    let openWorkout: (UUID) -> Void
    var calendar: Calendar = .current
    var now: Date = .now

    @ScaledMetric(relativeTo: .body) private var columnMinimum = 250
    @State private var width: CGFloat = 0

    /// Columns that fit `width` at the scaled minimum; an even number from two up, so the gutter falls on the fold
    /// and no card straddles it (`docs/port/duo-layout.md`, Grids).
    private var columnCount: Int {
        let spacing: CGFloat = 12
        let fit = max(1, Int(((width + spacing) / (columnMinimum + spacing)).rounded(.down)))
        return fit >= 3 && fit.isMultiple(of: 2) == false ? fit - 1 : fit
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: columnCount),
            alignment: .leading,
            spacing: 12
        ) {
            thisWeek
            recents
            if let last = HistoryDashboard.lastWorkout(entries: entries) {
                lastWorkout(last)
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
    }

    private var thisWeek: some View {
        let week = HistoryDashboard.thisWeek(entries: entries, calendar: calendar, now: now)
        let duration = HistoryList.durationText(seconds: week.durationSeconds)
        let volume = HistoryList.volumeText(week.volume, unit: week.unit)
        return DashboardCard(
            title: "This Week",
            systemImage: "calendar",
            label:
                "This week, \(week.workouts) of \(goal) workouts, \(duration), \(volume)",
            identifier: "history.card.thisWeek"
        ) {
            CardValue(text: "\(week.workouts) / \(goal)")
            Text(week.workouts == 1 ? "workout" : "workouts")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(duration) · \(volume)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var recents: some View {
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

    private func lastWorkout(_ entry: HistoryEntry) -> some View {
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
