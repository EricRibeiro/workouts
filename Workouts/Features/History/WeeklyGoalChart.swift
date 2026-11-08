//
//  WeeklyGoalChart.swift
//  Workouts
//

import Charts
import SwiftUI
import WorkoutsKit

/// The History list's first row (task 5.2): the weekly goal chart as a card. Reads the goal from Settings and cuts the
/// weeks in the device calendar, so a Settings change or a time zone change redraws it.
struct WeeklyGoalSection: View {
    /// Start dates of the finished workouts.
    let starts: [Date]

    @AppStorage(SettingsKey.weeklyGoal.rawValue) private var storedGoal = SettingsStore.weeklyGoalDefault

    var body: some View {
        let calendar = Calendar.current
        WeeklyGoalChart(
            counts: weeklyCounts(workouts: starts, calendar: calendar, now: .now),
            goal: min(max(storedGoal, 1), 14),
            calendar: calendar
        )
    }
}

/// Workouts per week for the last 8 Monday-first weeks: a bar per week (solid once it reaches the goal, lighter
/// before), the count above each non-empty bar, and a dashed goal line. Presentational: the caller supplies the counts.
struct WeeklyGoalChart: View {
    let counts: [WeekCount]
    let goal: Int
    var calendar: Calendar = .current

    @ScaledMetric(relativeTo: .body) private var plotHeight = 150
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chart
        }
        .dashboardCardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .accessibilityIdentifier("history.weeklyChart")
    }

    private var header: some View {
        Text("Workouts per week")
            .font(.headline)
    }

    private var chart: some View {
        let top = axisTop(counts: counts, goal: goal)
        let step = max(1, Int((Double(top) / 5).rounded(.up)))
        // Read here: the axis closure runs inside Charts, outside this view's environment (no Dynamic Type size there).
        let xLabels = labelledWeeks
        return Chart {
            ForEach(counts, id: \.weekStart) { week in
                BarMark(
                    x: .value("Week of", weekLabel(week.weekStart, calendar: calendar)),
                    y: .value("Workouts", week.count)
                )
                .foregroundStyle(week.count >= goal ? Color.accentColor : Color.chartBelowGoal)
                .cornerRadius(4)
                .annotation(position: .top, spacing: 2) {
                    if week.count > 0 {
                        Text("\(week.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            RuleMark(y: .value("Goal", goal))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.secondary)
        }
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(values: Array(stride(from: 0, through: top, by: step))) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks { value in
                // Only the weeks in `xLabels` are named (every week at normal sizes), so no label collides with a
                // neighbour or leaves the card at accessibility sizes; greedy resolution still guards the rest.
                AxisValueLabel(collisionResolution: .greedy) {
                    if let label = value.as(String.self), xLabels.contains(label) {
                        Text(label)
                    }
                }
            }
        }
        .frame(height: plotHeight)
    }

    /// The x labels to draw. Every week at normal sizes; at accessibility sizes every second week (every third past six
    /// weeks) counted back from the newest, leaving out the two outermost bars: their wide labels would run past the
    /// card's inset on the left and into the value axis on the right. The bar counts and the VoiceOver summary still
    /// cover every week.
    private var labelledWeeks: [String] {
        let labels = counts.map { weekLabel($0.weekStart, calendar: calendar) }
        guard typeSize.isAccessibilitySize else { return labels }
        let stride = labels.count > 6 ? 3 : 2
        return labels.indices.filter { $0 > 0 && $0 < labels.count - 1 && (labels.count - 1 - $0) % stride == 0 }
            .map { labels[$0] }
    }

    /// One sentence for VoiceOver: every week with its Monday, then the goal.
    private var summary: String {
        let weeks = counts.map { "week of \(weekLabel($0.weekStart, calendar: calendar)), \($0.count)" }
        return "Workouts per week, last \(counts.count) weeks: " + weeks.joined(separator: "; ") + "; goal \(goal)"
    }
}

#if DEBUG
    private enum WeeklyChartSample {
        static let counts: [WeekCount] = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Toronto") ?? .current
            let monday = DateComponents(calendar: calendar, year: 2026, month: 11, day: 2).date ?? .now
            return [2, 3, 4, 0, 1, 3, 5, 2].enumerated().map { index, count in
                WeekCount(
                    weekStart: calendar.date(byAdding: .weekOfYear, value: index - 7, to: monday) ?? monday,
                    count: count
                )
            }
        }()
        static let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Toronto") ?? .current
            return calendar
        }()
    }

    #Preview("Large") {
        WeeklyGoalChart(counts: WeeklyChartSample.counts, goal: 3, calendar: WeeklyChartSample.calendar)
            .padding()
            .dynamicTypeSize(.large)
    }

    #Preview("Accessibility 3") {
        WeeklyGoalChart(counts: WeeklyChartSample.counts, goal: 3, calendar: WeeklyChartSample.calendar)
            .padding()
            .dynamicTypeSize(.accessibility3)
    }
#endif
