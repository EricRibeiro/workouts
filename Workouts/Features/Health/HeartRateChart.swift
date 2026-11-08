//
//  HeartRateChart.swift
//  Workouts
//

import Charts
import SwiftUI
import WorkoutsKit

/// The finished-workout heart-rate chart: the Health series as a line, drawn over the workout's own set timeline (a
/// shaded band per exercise, a tick per completed set), the average and max beneath, and the time in each zone.
///
/// Everything is on one time axis in seconds from the Fitness workout's start, so build `timeline` with
/// `SetTimeline.make(…, origin: summary.start)`. Heart-rate samples before zero are dropped (the last one is kept at zero). The caller places the view
/// (it draws no card of its own) and checks `canShow(series:)` first.
struct HeartRateChart: View {
    let series: [HeartRatePoint]
    let timeline: SetTimeline
    var average: Double?
    var maximum: Double?
    var zones: [HeartRateZoneTime] = []

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selection: Double?

    /// A line needs two points; with fewer the caller leaves the chart out.
    static func canShow(series: [HeartRatePoint]) -> Bool { series.count >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chart
            caption
            zoneSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A container, so the zones keep their own identifier (a bare identifier here would replace it).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("heartRateChart")
    }

    // MARK: Data

    /// The series sorted by time, from the workout's start: samples before it are dropped except the last, kept at zero.
    private var points: [HeartRatePoint] {
        HeartRateSeries.clippedToStart(series)
    }

    /// The peak of what is plotted, so the "Max" caption never exceeds the line (the stored max can sit in the dropped lead-in).
    private var shownMaximum: Double? {
        HeartRateSeries.plottedMaximum(of: points, storedMaximum: maximum)
    }

    /// The time-weighted mean of what is plotted, so "Avg" covers the same span as "Max".
    private var shownAverage: Double? {
        HeartRateSeries.plottedAverage(of: points, storedAverage: average)
    }

    private var blocks: [SetTimeline.Block] {
        timeline.blocks.map {
            var block = $0
            block.start = max(0, $0.start)
            block.end = max(0, $0.end)
            return block
        }
    }

    private var xMax: Double {
        max(points.last?.offset ?? 0, blocks.map(\.end).max() ?? 0, 1)
    }

    /// Whole-minute-ish tick positions that read as m:ss: at most six, or three at accessibility sizes, where wider
    /// labels would truncate.
    private var xTicks: [Double] {
        let steps: [Double] = [60, 120, 300, 600, 900, 1200, 1800, 3600, 7200]
        let intervals = typeSize.isAccessibilitySize ? 2.0 : 5.0
        let step = steps.first { xMax / $0 <= intervals } ?? 7200
        return Array(stride(from: 0, through: xMax, by: step))
    }

    /// Narrowest share of the axis a band may cover and still carry its label; thinner bands would clip or collide.
    private static let minLabelFraction = 0.08

    private func labelFits(_ block: SetTimeline.Block) -> Bool {
        (block.end - block.start) / xMax >= Self.minLabelFraction
    }

    /// Supersets are tinted with their number's colour (as on the logging screen); other exercises alternate shades.
    private static func bandFill(_ block: SetTimeline.Block, position: Int) -> Color {
        if let number = block.supersetNumber { return Color.superset(number).opacity(0.18) }
        return position.isMultiple(of: 2) ? Color(.quaternarySystemFill) : Color(.quaternarySystemFill).opacity(0.5)
    }

    private var selectedPoint: HeartRatePoint? {
        guard let selection else { return nil }
        return points.min { abs($0.offset - selection) < abs($1.offset - selection) }
    }

    private func selectionText(_ point: HeartRatePoint) -> String {
        var text = "\(FitnessFormat.wholeNumber(point.bpm)) bpm"
        if let tick = timeline.set(at: selection ?? point.offset) {
            text += " \u{00B7} \(tick.blockName) set \(tick.setNumber)"
        }
        return text
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            ForEach(Array(blocks.enumerated()), id: \.offset) { position, block in
                RectangleMark(xStart: .value("Start", block.start), xEnd: .value("End", block.end))
                    .foregroundStyle(Self.bandFill(block, position: position))
                    .annotation(position: .overlay, alignment: .topLeading, spacing: 2) {
                        if horizontalSizeClass == .regular, labelFits(block) {
                            Text(block.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.leading, 2)
                        }
                    }
            }
            ForEach(Array(timeline.setTicks.enumerated()), id: \.offset) { _, tick in
                RuleMark(x: .value("Set", max(0, tick.offset)))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Time", point.offset), y: .value("Heart rate", point.bpm))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let point = selectedPoint {
                RuleMark(x: .value("Selected", point.offset))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color(.secondaryLabel))
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        Text(selectionText(point))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                PointMark(x: .value("Selected", point.offset), y: .value("Heart rate", point.bpm))
                    .symbolSize(40)
                    .foregroundStyle(.red)
            }
        }
        .chartXSelection(value: $selection)
        .chartXScale(domain: 0...xMax)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: xTicks) { value in
                AxisTick()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(ClockFormat.clock(seconds: seconds))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Color(.separator))
                AxisValueLabel().font(.caption2)
            }
        }
        .frame(height: 120)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = "Heart rate"
        var parts: [String] = []
        if let shownAverage { parts.append("average \(FitnessFormat.wholeNumber(shownAverage))") }
        if let shownMaximum { parts.append("max \(FitnessFormat.wholeNumber(shownMaximum))") }
        if !parts.isEmpty { text += ", " + parts.joined(separator: ", ") + " beats per minute" }
        if !timeline.isEmpty {
            text +=
                ", \(timeline.setTicks.count) \(timeline.setTicks.count == 1 ? "set" : "sets") across \(timeline.blocks.count) \(timeline.blocks.count == 1 ? "exercise" : "exercises")"
        }
        return text
    }

    // MARK: Caption

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(captionText)
                .font(.footnote)
                .monospacedDigit()
            Text("Data from Apple Health")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var captionText: String {
        var parts = ["Heart Rate"]
        if let shownAverage { parts.append("Avg \(FitnessFormat.wholeNumber(shownAverage))") }
        if let shownMaximum { parts.append("Max \(FitnessFormat.wholeNumber(shownMaximum))") }
        var text = parts.joined(separator: " \u{00B7} ")
        if shownAverage != nil || shownMaximum != nil { text += " bpm" }
        return text
    }

    // MARK: Zones

    @ViewBuilder
    private var zoneSection: some View {
        let summary = ZoneSummary(zones: zones)
        if summary.isMeaningful {
            VStack(alignment: .leading, spacing: 8) {
                zoneBar(summary.zonesWithTime)
                zoneLegend(summary.zonesWithTime)
            }
            .padding(.top, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Heart rate zones: " + summary.zonesWithTime.map(FitnessFormat.zoneSentence).joined(separator: "; ")
            )
            .accessibilityIdentifier("heartRateChart.zones")
        } else if let text = summary.caption {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("heartRateChart.zones")
        }
    }

    private func zoneBar(_ zones: [HeartRateZoneTime]) -> some View {
        Chart(zones, id: \.index) { zone in
            BarMark(x: .value("Time", zone.seconds), y: .value("Zones", "Zones"))
                .foregroundStyle(Self.zoneColor(zone.index))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 16)
        .clipShape(Capsule())
    }

    /// A wrapping grid of items at regular sizes; one item per line at accessibility sizes, where a grid cell would
    /// wrap "Zone 1 · 30:00" mid-item.
    @ViewBuilder
    private func zoneLegend(_ zones: [HeartRateZoneTime]) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(zones, id: \.index) { zoneLegendItem($0) }
            }
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)],
                alignment: .leading,
                spacing: 4
            ) {
                ForEach(zones, id: \.index) { zoneLegendItem($0) }
            }
        }
    }

    private func zoneLegendItem(_ zone: HeartRateZoneTime) -> some View {
        Label {
            Text(ZoneSummary.legendText(zone))
                .font(.caption)
                .monospacedDigit()
        } icon: {
            Circle()
                .fill(Self.zoneColor(zone.index))
                .frame(width: 8, height: 8)
        }
    }

    /// Cool to hot, lowest effort first; zones past five reuse the last colour.
    private static func zoneColor(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .teal, .green, .orange, .red]
        return colors[min(max(index, 1), colors.count) - 1]
    }
}

#if DEBUG
    /// Sample charts for the gallery (`-preview HeartRateChart`) and the preview: plain exercises around an interleaved
    /// superset (Lateral Raise and Triceps Pushdown alternate set by set), once on a full axis and once on a short one.
    struct HeartRateChartDemo: View {
        private static func at(_ origin: Date, _ seconds: [TimeInterval]) -> [Date?] {
            seconds.map { origin.addingTimeInterval($0) }
        }

        /// The sample heart-rate series and set timeline, also what the snapshot tests draw.
        static let sample: (series: [HeartRatePoint], timeline: SetTimeline) = {
            let origin = Date(timeIntervalSinceReferenceDate: 0)
            let count = 90
            let duration: TimeInterval = 2400
            let series = (0..<count).map { index -> HeartRatePoint in
                let progress = Double(index) / Double(count - 1)
                let ramp = 70 + 45 * min(1, progress * 4)
                let waves = 18 * sin(progress * 14 * .pi)
                let peak = 25 * max(0, 1 - abs(progress - 0.85) * 10)
                return HeartRatePoint(offset: progress * duration, bpm: (ramp + waves + peak).rounded())
            }
            let timeline = SetTimeline.make(
                origin: origin,
                blocks: [
                    .init(name: "Bench Press", completions: at(origin, [300, 420, 540, 660])),
                    .init(
                        name: "Cable Triceps Pushdown",
                        supersetGroup: 1,
                        completions: at(origin, [800, 920, 1040])
                    ),
                    .init(
                        name: "Dumbbell Lateral Raise",
                        supersetGroup: 1,
                        completions: at(origin, [860, 980, 1100])
                    ),
                    .init(name: "Seated Cable Row", completions: at(origin, [1250, 1370, 1490])),
                    .init(name: "Overhead Press", completions: at(origin, [1700, 1820, 1940, 2060])),
                ]
            )
            return (series, timeline)
        }()

        var body: some View {
            let (series, timeline) = Self.sample
            ScrollView {
                VStack(spacing: 24) {
                    HeartRateChart(
                        series: series,
                        timeline: timeline,
                        average: 118,
                        maximum: 161,
                        zones: [
                            HeartRateZoneTime(index: 1, upperBPM: 138, seconds: 1800),
                            HeartRateZoneTime(index: 2, lowerBPM: 139, upperBPM: 150, seconds: 525),
                            HeartRateZoneTime(index: 3, lowerBPM: 151, upperBPM: 162, seconds: 75),
                        ]
                    )
                    HeartRateChart(
                        series: series,
                        timeline: timeline,
                        average: 96,
                        maximum: 121,
                        zones: [HeartRateZoneTime(index: 1, upperBPM: 139, seconds: 2400)]
                    )
                }
                .padding()
            }
            .accessibilityIdentifier("screen.heartRateChart")
        }
    }

    #Preview("Heart rate chart") {
        HeartRateChartDemo()
    }
#endif
