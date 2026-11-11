//
//  WeeklyGoalChart.swift
//  Workouts
//

import Charts
import SwiftUI
import WorkoutsKit

/// What the History chart card plots: the workout count per week against the goal, or the weekly volume against its
/// 4-week average.
enum WeeklyChartMode: String, CaseIterable, Identifiable {
    case workouts
    case volume

    var id: Self { self }

    var title: String {
        switch self {
        case .workouts: "Workouts"
        case .volume: "Volume"
        }
    }
}

/// The History list's first row (task 5.2): the weekly chart as a card. Reads the goal from Settings and cuts the weeks
/// in the device calendar, so a Settings change or a time zone change redraws it. The mode is kept per scene.
struct WeeklyGoalSection: View {
    /// Start dates of the finished workouts.
    let starts: [Date]
    /// The finished workouts' rows (the volume view).
    var entries: [HistoryEntry] = []

    @AppStorage(SettingsKey.weeklyGoal.rawValue) private var storedGoal = SettingsStore.weeklyGoalDefault
    @SceneStorage("history.chartMode") private var mode = WeeklyChartMode.workouts

    var body: some View {
        let calendar = Calendar.current
        // Twelve weeks so each of the eight shown has four before it to average.
        let totals = HistoryDashboard.weeklyTotals(entries: entries, weeks: 12, calendar: calendar, now: .now)
        let averages = HistoryDashboard.trailingAverages(totals.map(\.volume), window: 4)
        WeeklyGoalChart(
            mode: $mode,
            counts: weeklyCounts(workouts: starts, calendar: calendar, now: .now),
            goal: min(max(storedGoal, 1), 14),
            volume: Array(totals.suffix(8)),
            averages: Array(averages.suffix(8)),
            unit: entries.first?.unit ?? .kg,
            calendar: calendar
        )
    }
}

/// The last 8 Monday-first weeks as a card with a Workouts / Volume switch. Workouts: a bar per week (lime once it
/// reaches the goal, gray before), the count above each non-empty bar, and a dashed goal line. Volume: a bar per week
/// (lime at or above its 4-week average or when it has none yet, gray below) and the average as a line. Presentational: the caller supplies the data.
struct WeeklyGoalChart: View {
    @Binding var mode: WeeklyChartMode
    let counts: [WeekCount]
    let goal: Int
    /// The same weeks as `counts`, with their volume.
    var volume: [WeekTotal] = []
    /// For each of `volume`'s weeks, the mean volume of the four weeks before it; nil when fewer precede it.
    var averages: [Double?] = []
    var unit: WeightUnit = .kg
    var calendar: Calendar = .current

    @ScaledMetric(relativeTo: .body) private var plotHeight = 150
    @ScaledMetric(relativeTo: .caption) private var swatchWidth = 16
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(alignment: .leading, spacing: 8) {
                switch mode {
                case .workouts: workoutsChart
                case .volume:
                    volumeChart
                    legend
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
            .accessibilityIdentifier("history.weeklyChart")
        }
        .dashboardCardStyle()
    }

    /// The title and the mode switch on one row; at accessibility sizes the switch moves below the title at full width.
    private var header: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout =
            stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text("Per week")
                .font(.headline)
            if !stacked { Spacer(minLength: 0) }
            modePicker.fixedSize(horizontal: !stacked, vertical: false)
        }
    }

    private var modePicker: some View {
        Picker("Chart", selection: $mode) {
            ForEach(WeeklyChartMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("history.weeklyChart.mode")
    }

    // MARK: Workouts

    private var workoutsChart: some View {
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
        .chartXAxis { weekAxis(xLabels) }
        .frame(height: plotHeight)
    }

    // MARK: Volume

    private var hasAverage: Bool { averages.contains { $0 != nil } }

    private var volumeChart: some View {
        let axis = HistoryDashboard.volumeAxis(totals: volume, averages: averages)
        let xLabels = labelledWeeks
        // Every second gridline at accessibility sizes, where the labels would squeeze the plot.
        let ticks = typeSize.isAccessibilitySize ? axis.thinned(every: 2) : axis.ticks
        return Chart {
            ForEach(volume, id: \.weekStart) { week in
                BarMark(
                    x: .value("Week of", weekLabel(week.weekStart, calendar: calendar)),
                    y: .value("Volume", week.volume)
                )
                .foregroundStyle(isBelowAverage(week) ? Color.chartBelowGoal : Color.accentColor)
                .cornerRadius(4)
            }
            ForEach(Array(volume.enumerated()), id: \.element.weekStart) { index, week in
                if index < averages.count, let average = averages[index] {
                    let x = PlottableValue.value("Week of", weekLabel(week.weekStart, calendar: calendar))
                    LineMark(x: x, y: .value("4-week average", average), series: .value("Series", "Average"))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Color.primary.opacity(0.8))
                    PointMark(x: x, y: .value("4-week average", average))
                        .symbolSize(28)
                        .foregroundStyle(Color.primary.opacity(0.8))
                }
            }
        }
        .chartYScale(domain: 0...axis.top)
        .chartYAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(HistoryList.compactVolumeText(amount))
                    }
                }
            }
        }
        .chartXAxis { weekAxis(xLabels) }
        .frame(height: plotHeight)
    }

    /// True when the week has a 4-week average and its volume is under it.
    private func isBelowAverage(_ week: WeekTotal) -> Bool {
        guard let index = volume.firstIndex(where: { $0.weekStart == week.weekStart }), index < averages.count,
            let average = averages[index]
        else { return false }
        return week.volume < average
    }

    /// The line's swatch and name, then the unit the axis is in; just the unit when no week has an average yet.
    private var legend: some View {
        HStack(spacing: 6) {
            if hasAverage {
                Capsule()
                    .fill(Color.primary.opacity(0.8))
                    .frame(width: swatchWidth, height: 2)
                    .accessibilityHidden(true)
                Text("4-week average, \(unit.rawValue)")
            } else {
                Text(unit.rawValue)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Shared

    private func weekAxis(_ xLabels: [String]) -> some AxisContent {
        AxisMarks { value in
            // Only the weeks in `xLabels` are named (every week at normal sizes), so none collides with a neighbour or
            // leaves the card at accessibility sizes. Collision resolution is off: it dropped labels that fit.
            AxisValueLabel(collisionResolution: .disabled) {
                if let label = value.as(String.self), xLabels.contains(label) {
                    Text(label)
                }
            }
        }
    }

    /// The x labels to draw. Every week at normal sizes; at accessibility sizes every second week (every third past six
    /// weeks) counted back from the newest, leaving out the two outermost bars: their wide labels would run past the
    /// card's inset on the left and into the value axis on the right. The bars and the VoiceOver summary still cover
    /// every week.
    private var labelledWeeks: [String] {
        let weeks = mode == .workouts ? counts.map(\.weekStart) : volume.map(\.weekStart)
        let labels = weeks.map { weekLabel($0, calendar: calendar) }
        guard typeSize.isAccessibilitySize else { return labels }
        let stride = labels.count > 6 ? 3 : 2
        return labels.indices.filter { $0 > 0 && $0 < labels.count - 1 && (labels.count - 1 - $0) % stride == 0 }
            .map { labels[$0] }
    }

    /// One sentence for VoiceOver: every week with its Monday, then the goal (workouts) or the latest average (volume).
    private var summary: String {
        switch mode {
        case .workouts:
            let weeks = counts.map { "week of \(weekLabel($0.weekStart, calendar: calendar)), \($0.count)" }
            return "Workouts per week, last \(counts.count) weeks: " + weeks.joined(separator: "; ") + "; goal \(goal)"
        case .volume:
            let weeks = volume.map {
                "week of \(weekLabel($0.weekStart, calendar: calendar)), \(HistoryList.volumeText($0.volume, unit: unit))"
            }
            var text = "Volume per week, last \(volume.count) weeks: " + weeks.joined(separator: "; ")
            if let average = averages.last, let average {
                text += "; 4-week average \(HistoryList.volumeText(average, unit: unit))"
            }
            return text
        }
    }
}

#if DEBUG
    private enum WeeklyChartSample {
        static let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Toronto") ?? .current
            return calendar
        }()
        static let mondays: [Date] = {
            let monday = DateComponents(calendar: calendar, year: 2026, month: 11, day: 2).date ?? .now
            return (0..<8).map { calendar.date(byAdding: .weekOfYear, value: $0 - 7, to: monday) ?? monday }
        }()
        static let counts: [WeekCount] = zip(mondays, [2, 3, 4, 0, 1, 3, 5, 2]).map {
            WeekCount(weekStart: $0, count: $1)
        }
        static let volume: [WeekTotal] = zip(mondays, [14_200, 18_650, 22_318, 0, 9_400, 19_800, 25_100, 12_300])
            .map { WeekTotal(weekStart: $0, workouts: 1, durationSeconds: 3600, volume: $1) }
        static let averages: [Double?] = [nil, nil, nil, 18_900, 17_300, 12_900, 12_900, 13_650]
    }

    private struct WeeklyChartPreview: View {
        @State var mode: WeeklyChartMode
        var body: some View {
            WeeklyGoalChart(
                mode: $mode,
                counts: WeeklyChartSample.counts,
                goal: 3,
                volume: WeeklyChartSample.volume,
                averages: WeeklyChartSample.averages,
                unit: .lb,
                calendar: WeeklyChartSample.calendar
            )
            .padding()
        }
    }

    #Preview("Large") {
        WeeklyChartPreview(mode: .workouts).dynamicTypeSize(.large)
    }

    #Preview("Accessibility 3") {
        WeeklyChartPreview(mode: .workouts).dynamicTypeSize(.accessibility3)
    }

    #Preview("Volume") {
        WeeklyChartPreview(mode: .volume).dynamicTypeSize(.large)
    }

    #Preview("Volume, Accessibility 3") {
        WeeklyChartPreview(mode: .volume).dynamicTypeSize(.accessibility3)
    }
#endif
