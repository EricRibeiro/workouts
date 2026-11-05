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
/// `SetTimeline.make(…, origin: summary.start)`. Offsets before zero are clamped to zero. The caller places the view
/// (it draws no card of its own) and checks `canShow(series:)` first.
struct HeartRateChart: View {
    let series: [HeartRatePoint]
    let timeline: SetTimeline
    var average: Double?
    var maximum: Double?
    var zones: [HeartRateZoneTime] = []

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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

    /// The series sorted by time with negative offsets clamped to zero.
    private var points: [HeartRatePoint] {
        series.map { HeartRatePoint(offset: max(0, $0.offset), bpm: $0.bpm) }.sorted { $0.offset < $1.offset }
    }

    private var blocks: [SetTimeline.Block] {
        timeline.blocks.map { .init(name: $0.name, start: max(0, $0.start), end: max(0, $0.end)) }
    }

    private var xMax: Double {
        max(points.last?.offset ?? 0, blocks.map(\.end).max() ?? 0, 1)
    }

    /// Whole-minute-ish tick positions, at most five, that read as m:ss.
    private var xTicks: [Double] {
        let steps: [Double] = [60, 120, 300, 600, 900, 1200, 1800, 3600, 7200]
        let step = steps.first { xMax / $0 <= 5 } ?? 7200
        return Array(stride(from: 0, through: xMax, by: step))
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
                    .foregroundStyle(
                        position.isMultiple(of: 2)
                            ? Color(.quaternarySystemFill) : Color(.quaternarySystemFill).opacity(0.5)
                    )
                    .annotation(position: .overlay, alignment: .topLeading, spacing: 2) {
                        if horizontalSizeClass == .regular {
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
        if let average { parts.append("average \(FitnessFormat.wholeNumber(average))") }
        if let maximum { parts.append("max \(FitnessFormat.wholeNumber(maximum))") }
        if !parts.isEmpty { text += ", " + parts.joined(separator: ", ") + " beats per minute" }
        if !timeline.isEmpty { text += ", \(timeline.setTicks.count) sets across \(timeline.blocks.count) exercises" }
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
        if let average { parts.append("Avg \(FitnessFormat.wholeNumber(average))") }
        if let maximum { parts.append("Max \(FitnessFormat.wholeNumber(maximum))") }
        var text = parts.joined(separator: " \u{00B7} ")
        if average != nil || maximum != nil { text += " bpm" }
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

    private func zoneLegend(_ zones: [HeartRateZoneTime]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(zones, id: \.index) { zone in
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
        }
    }

    /// Cool to hot, lowest effort first; zones past five reuse the last colour.
    private static func zoneColor(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .teal, .green, .orange, .red]
        return colors[min(max(index, 1), colors.count) - 1]
    }
}

#Preview("Heart rate chart") {
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
            .init(name: "Bench Press", completions: [300, 420, 540, 660].map { origin.addingTimeInterval($0) }),
            .init(name: "Seated Cable Row", completions: [900, 1020, 1140].map { origin.addingTimeInterval($0) }),
            .init(name: "Overhead Press", completions: [1500, 1620, 1740, 1860].map { origin.addingTimeInterval($0) }),
        ]
    )
    return ScrollView {
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
}
