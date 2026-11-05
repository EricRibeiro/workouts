//
//  ExerciseChartsView.swift
//  Workouts
//

import Accessibility
import Charts
import SwiftUI
import WorkoutsKit

/// The Charts segment (task 4.3): one point per session for the chosen metric, a line with point marks over time, a
/// readout for the selected (default newest) point, metric chips and a range control
/// (`docs/port/screens/exercises.md` section 2, "Charts tab"). Values come from the kit's `chartSeries`, already in the
/// display unit.
struct ExerciseChartsView: View {
    let sessions: [Session]
    let weightType: WeightType
    let options: RecordsOptions

    @State private var metric: ChartMetric
    @State private var range = ChartRange.standard
    @State private var selectedDate: Date?
    @ScaledMetric(relativeTo: .body) private var plotHeight = 220
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(sessions: [Session], weightType: WeightType, options: RecordsOptions) {
        self.sessions = sessions
        self.weightType = weightType
        self.options = options
        _metric = State(initialValue: ChartMetric.defaultMetric(for: weightType.category))
    }

    private var category: WeightCategory { weightType.category }
    private var unit: String { options.displayUnit.rawValue }
    private var metricTitle: String { metric.title(for: category) }

    private var points: [ChartPoint] {
        range.filter(chartSeries(sessions, metric: metric, options: options), now: .now)
    }

    var body: some View {
        let points = points
        VStack(alignment: .leading, spacing: 16) {
            chips
            Picker("Range", selection: $range) {
                ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Range")
            .accessibilityIdentifier("exerciseDetail.chart.range")
            if points.isEmpty {
                Text("Nothing to plot for \(metricTitle) in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("exerciseDetail.chart.empty")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    readout(selected(in: points))
                    chart(points)
                }
                .detailCardStyle()
            }
        }
        .onChange(of: metric) { selectedDate = nil }
        .onChange(of: range) { selectedDate = nil }
    }

    // MARK: Chips

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChartMetric.available(for: category), id: \.self) { candidate in
                    let selected = candidate == metric
                    Button {
                        metric = candidate
                    } label: {
                        Text(candidate.title(for: category))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(selected ? .accentColor : .secondary)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("exerciseDetail.chart.metric.\(candidate.rawValue)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exerciseDetail.chart.metric")
    }

    // MARK: Readout

    private func selected(in points: [ChartPoint]) -> ChartPoint? {
        guard let selectedDate else { return points.last }
        return points.min {
            abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate))
        }
    }

    private func valueText(_ value: Double) -> String {
        if metric.isWeightValued { return "\(HistoryDashboard.groupedWeight(value)) \(unit)" }
        let count = Int(value.rounded())
        return "\(count) \(count == 1 ? "rep" : "reps")"
    }

    @ViewBuilder
    private func readout(_ point: ChartPoint?) -> some View {
        if let point {
            let layout =
                dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metricTitle).font(.headline)
                    Text(RecordFormat.date(point.time)).font(.footnote).foregroundStyle(.secondary)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                    Text(valueText(point.value))
                        .font(.title3.weight(.semibold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                    if point.lowConfidence {
                        Text("from over 12 reps").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                [
                    metricTitle, RecordFormat.date(point.time), valueText(point.value),
                    point.lowConfidence ? "from over 12 reps" : nil,
                ].compactMap { $0 }.joined(separator: ", ")
            )
            .accessibilityIdentifier("exerciseDetail.chart.readout")
        }
    }

    // MARK: Chart

    private func chart(_ points: [ChartPoint]) -> some View {
        let highlighted = selected(in: points)
        return Chart {
            ForEach(points, id: \.self) { point in
                LineMark(x: .value("Date", point.time), y: .value(metricTitle, point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.tint)
                PointMark(x: .value("Date", point.time), y: .value(metricTitle, point.value))
                    .symbolSize(point == highlighted ? 110 : 40)
                    .foregroundStyle(.tint)
            }
            if let highlighted {
                RuleMark(x: .value("Date", highlighted.time))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: plotHeight)
        .accessibilityChartDescriptor(
            SessionChartDescriptor(
                title: "\(metricTitle) by session",
                valueTitle: metric.isWeightValued ? "\(metricTitle) (\(unit))" : metricTitle,
                points: points
            )
        )
        .accessibilityIdentifier("exerciseDetail.chart")
    }
}

/// The VoiceOver audio-graph description of the chart: date on the x axis, the metric on the y axis.
private struct SessionChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let valueTitle: String
    let points: [ChartPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let times = points.map { $0.time.timeIntervalSince1970 }
        let values = points.map(\.value)
        let lowerX = times.min() ?? 0
        let upperX = max(times.max() ?? 0, lowerX + 86_400)
        let lowerY = values.min() ?? 0
        let upperY = max(values.max() ?? 0, lowerY + 1)
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Date",
            range: lowerX...upperX,
            gridlinePositions: []
        ) { value in
            Date(timeIntervalSince1970: value).formatted(.dateTime.month(.abbreviated).day().year())
        }
        let yAxis = AXNumericDataAxisDescriptor(
            title: valueTitle,
            range: lowerY...upperY,
            gridlinePositions: []
        ) { value in
            SetInputFormat.weightText(value)
        }
        let series = AXDataSeriesDescriptor(
            name: title,
            isContinuous: true,
            dataPoints: points.map { AXDataPoint(x: $0.time.timeIntervalSince1970, y: $0.value) }
        )
        return AXChartDescriptor(
            title: title,
            summary: "\(points.count) \(points.count == 1 ? "session" : "sessions")",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        descriptor.title = title
    }
}
