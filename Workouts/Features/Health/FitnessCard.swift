//
//  FitnessCard.swift
//  Workouts
//

import Charts
import SwiftUI
import WorkoutsKit

/// The Apple Fitness numbers matched to a workout (PLAN 7.1b f): active and total calories, average and maximum heart
/// rate and effort, a compact heart-rate line, the time in each heart-rate zone, and the weather as a footnote. Whatever
/// Health did not have is left out. Three accessibility elements, one per section: the stats with the chart (the
/// `fitness.card` summary), the zones and the weather. The chart is decoration.
struct FitnessCard: View {
    let summary: HealthWorkoutSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The narrowest a stat may get before the grid drops a column; it grows with Dynamic Type.
    @ScaledMetric(relativeTo: .title2) private var statMinimum = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statsAndChart
            if !summary.zones.isEmpty {
                zones
            }
            if let weather {
                weatherRow(weather)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Stats and chart

    private var statsAndChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: statColumns, alignment: .leading, spacing: 12) {
                if let calories = summary.activeEnergyKcal {
                    stat(
                        symbol: "flame.fill",
                        tint: .orange,
                        value: FitnessFormat.wholeNumber(calories),
                        unit: "kcal",
                        caption: "Active"
                    )
                }
                if let calories = summary.totalEnergyKcal {
                    stat(
                        symbol: "flame",
                        tint: .orange,
                        value: FitnessFormat.wholeNumber(calories),
                        unit: "kcal",
                        caption: "Total"
                    )
                }
                if let average = summary.avgHeartRate {
                    stat(
                        symbol: "heart.fill",
                        tint: .red,
                        value: FitnessFormat.wholeNumber(average),
                        unit: "bpm",
                        caption: "Average"
                    )
                }
                if let maximum = summary.maxHeartRate {
                    stat(
                        symbol: "heart.fill",
                        tint: .red,
                        value: FitnessFormat.wholeNumber(maximum),
                        unit: "bpm",
                        caption: "Max"
                    )
                }
                if let effort = summary.effort {
                    stat(
                        symbol: "gauge.with.dots.needle.67percent",
                        tint: .purple,
                        value: "\(FitnessFormat.wholeScore(effort.score))",
                        unit: effort.word,
                        caption: effort.isEstimated ? "Estimated effort" : "Effort"
                    )
                }
            }
            if summary.heartRateSeries.count > 1 {
                chart
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("fitness.card")
    }

    /// Adaptive columns, one column at the accessibility sizes.
    private var statColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .topLeading)]
            : [GridItem(.adaptive(minimum: statMinimum), spacing: 12, alignment: .topLeading)]
    }

    private func stat(symbol: String, tint: Color, value: String, unit: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(tint)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chart: some View {
        Chart(summary.heartRateSeries, id: \.offset) { point in
            LineMark(
                x: .value("Time", point.offset),
                y: .value("Heart rate", point.bpm)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.red)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 56)
        .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let calories = summary.activeEnergyKcal {
            parts.append("\(FitnessFormat.wholeNumber(calories)) active calories")
        }
        if let calories = summary.totalEnergyKcal {
            parts.append("\(FitnessFormat.wholeNumber(calories)) total calories")
        }
        if let average = summary.avgHeartRate {
            parts.append("average heart rate \(FitnessFormat.wholeNumber(average))")
        }
        if let maximum = summary.maxHeartRate { parts.append("maximum \(FitnessFormat.wholeNumber(maximum))") }
        if let effort = summary.effort {
            parts.append(
                "effort \(FitnessFormat.wholeScore(effort.score)) \(effort.word)"
                    + (effort.isEstimated ? ", estimated" : "")
            )
        }
        if !summary.zones.isEmpty { parts.append("\(summary.zones.count) zones") }
        return parts.isEmpty ? "Fitness" : "Fitness: " + parts.joined(separator: ", ")
    }

    // MARK: Zones

    /// One row per zone: its name and bpm range, the time, and a bar for its share of the time in all the zones.
    private var zones: some View {
        let shares = FitnessFormat.zoneShares(summary.zones)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Heart Rate Zones")
                .font(.subheadline.weight(.semibold))
            ForEach(Array(summary.zones.enumerated()), id: \.element.index) { position, zone in
                zoneRow(zone, share: shares[position])
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Heart rate zones: " + summary.zones.map(FitnessFormat.zoneSentence).joined(separator: "; ")
        )
        .accessibilityIdentifier("fitness.zones")
    }

    private func zoneRow(_ zone: HeartRateZoneTime, share: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Zone \(zone.index)")
                        .font(.subheadline)
                    if let range = FitnessFormat.zoneRangeText(zone) {
                        Text(range)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(FitnessFormat.clockText(seconds: zone.seconds))
                    .font(.subheadline.monospacedDigit())
            }
            ProgressView(value: share)
                .tint(Self.zoneColor(zone.index))
        }
    }

    /// Cool to hot, lowest effort first; zones past five reuse the last colour.
    private static func zoneColor(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .teal, .green, .orange, .red]
        return colors[min(max(index, 1), colors.count) - 1]
    }

    // MARK: Weather

    private var weather: String? {
        FitnessFormat.weatherText(
            celsius: summary.weatherTemperatureCelsius,
            humidityPercent: summary.weatherHumidityPercent
        )
    }

    /// The temperature and humidity as a small footnote row; stacks when the text is large.
    private func weatherRow(_ spoken: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { weatherItems }
            VStack(alignment: .leading, spacing: 4) { weatherItems }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weather: " + spoken)
        .accessibilityIdentifier("fitness.weather")
    }

    @ViewBuilder
    private var weatherItems: some View {
        if let celsius = summary.weatherTemperatureCelsius {
            Label(FitnessFormat.temperatureText(celsius: celsius), systemImage: "thermometer.medium")
        }
        if let humidity = summary.weatherHumidityPercent {
            Label(FitnessFormat.humidityText(percent: humidity), systemImage: "humidity")
        }
    }
}

#if DEBUG
    /// The gallery entry `FitnessCard`: runs `HealthEnrichment` against a `HealthFixture` (`-healthFixture <name>`, default
    /// `full`) for a sample interval and shows what a workout screen would. With `-healthReal` it reads the simulator's real
    /// Health store instead (after `-seedHealth` finishes, if passed): the real-store integration test's subject.
    struct FitnessCardDemo: View {
        private enum Phase {
            case loading
            case loaded(HealthWorkoutSummary)
            case noWorkout
            case denied
            case failed
        }

        var fixture: HealthFixture = HealthFixture.requested() ?? .full

        var useRealStore = ProcessInfo.processInfo.arguments.contains("-healthReal")

        @State private var phase = Phase.loading

        var body: some View {
            List {
                Section("Apple Fitness") {
                    switch phase {
                    case .loading:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Loading Fitness workout")
                            .accessibilityIdentifier("fitness.loading")
                    case .loaded(let summary):
                        FitnessCard(summary: summary)
                    case .noWorkout:
                        Text("No Fitness workout")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("fitness.none")
                    case .denied:
                        Text("Health access off")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("fitness.denied")
                    case .failed:
                        Text("Could not read Health")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("fitness.failed")
                    }
                }
            }
            .accessibilityIdentifier("screen.fitnessCardDemo")
            .task { await load() }
        }

        private func load() async {
            let end = Date.now
            let start = end.addingTimeInterval(-50 * 60)
            if useRealStore {
                // The seeder (if requested) writes the workout the read below must find.
                await HealthSeeder.seeding?.value
                let source = HealthKitSource()
                do {
                    try await source.requestReadAuthorization()
                } catch HealthSourceError.notAuthorized {
                    phase = .denied
                    return
                } catch {
                    phase = .failed
                    return
                }
                // The seed spans the last 50 minutes; read the last 60.
                await enrich(HealthEnrichment(source: source), start: end.addingTimeInterval(-60 * 60), end: end)
            } else {
                await enrich(HealthEnrichment(source: fixture.source(around: start, end: end)), start: start, end: end)
            }
        }

        private func enrich(_ enrichment: HealthEnrichment, start: Date, end: Date) async {
            do {
                if let summary = try await enrichment.enrich(workoutStart: start, workoutEnd: end) {
                    phase = .loaded(summary)
                } else {
                    phase = .noWorkout
                }
            } catch HealthSourceError.notAuthorized {
                phase = .denied
            } catch {
                phase = .failed
            }
        }
    }

    #Preview("Large") {
        PreviewGallery.host("FitnessCard")
            .dynamicTypeSize(.large)
    }

    #Preview("Accessibility 3") {
        PreviewGallery.host("FitnessCard")
            .dynamicTypeSize(.accessibility3)
    }
#endif
