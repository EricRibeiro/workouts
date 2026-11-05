//
//  FitnessCard.swift
//  Workouts
//

import Charts
import SwiftUI
import WorkoutsKit

/// The Apple Fitness numbers matched to a workout: active calories, average and maximum heart rate, and a compact
/// heart-rate line. Stats Health did not have are left out. One accessibility element; the chart is decoration.
struct FitnessCard: View {
    let summary: HealthWorkoutSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statsLayout {
                if let calories = summary.activeEnergyKcal {
                    stat(
                        symbol: "flame.fill",
                        tint: .orange,
                        value: Self.rounded(calories),
                        unit: "kcal",
                        caption: "Active"
                    )
                }
                if let average = summary.avgHeartRate {
                    stat(
                        symbol: "heart.fill",
                        tint: .red,
                        value: Self.rounded(average),
                        unit: "bpm",
                        caption: "Average"
                    )
                }
                if let maximum = summary.maxHeartRate {
                    stat(
                        symbol: "heart.fill",
                        tint: .red,
                        value: Self.rounded(maximum),
                        unit: "bpm",
                        caption: "Max"
                    )
                }
            }
            if summary.heartRateSeries.count > 1 {
                chart
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("fitness.card")
    }

    private var statsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
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
        if let calories = summary.activeEnergyKcal { parts.append("\(Self.rounded(calories)) active calories") }
        if let average = summary.avgHeartRate { parts.append("average heart rate \(Self.rounded(average))") }
        if let maximum = summary.maxHeartRate { parts.append("maximum \(Self.rounded(maximum))") }
        return parts.isEmpty ? "Fitness" : "Fitness: " + parts.joined(separator: ", ")
    }

    private static func rounded(_ value: Double) -> String {
        String(Int(value.rounded()))
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
                Section("Fitness") {
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
