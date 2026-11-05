//
//  HealthFixture.swift
//  Workouts
//

#if DEBUG
    import Foundation
    import WorkoutsKit

    /// Canned Health data for previews, the gallery and UI tests (`-healthFixture <name>`), so the enrichment path is provable
    /// without HealthKit or a paired watch.
    nonisolated enum HealthFixture: String, CaseIterable, Sendable {
        /// One strength workout overlapping the interval, with energy and a heart-rate series.
        case full
        /// Health is readable but holds no workout.
        case none
        /// Read access is off.
        case denied
        /// Like `full`, but every call takes two seconds.
        case slow

        /// The fixture named after `-healthFixture` in the launch arguments, if any.
        static func requested(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> HealthFixture? {
            guard let index = arguments.firstIndex(of: "-healthFixture"), arguments.indices.contains(index + 1) else {
                return nil
            }
            return HealthFixture(rawValue: arguments[index + 1])
        }

        /// How long before and after our workout the canned Fitness workout starts and stops, like the real thing.
        fileprivate static let fitnessLeadIn: TimeInterval = 45
        fileprivate static let fitnessTail: TimeInterval = 30

        /// A source that answers for any workout: it builds the fixture around the interval each query asks about, so a
        /// workout recorded during the run finds its own Fitness data. Use this where the workout is not known up front.
        var anyWorkoutSource: any HealthSource { HealthFixtureSource(fixture: self) }

        /// A source for a workout that ran from `start` to `end`.
        func source(around start: Date, end: Date) -> FakeHealthSource {
            switch self {
            case .none:
                return FakeHealthSource()
            case .denied:
                return .failing(.notAuthorized)
            case .full:
                return Self.fullSource(around: start, end: end)
            case .slow:
                var source = Self.fullSource(around: start, end: end)
                source.delay = .seconds(2)
                return source
            }
        }

        private static func fullSource(around start: Date, end: Date) -> FakeHealthSource {
            // Fitness is started a little before and stopped a little after ours, like the real thing.
            let fitnessStart = start.addingTimeInterval(-fitnessLeadIn)
            let fitnessEnd = end.addingTimeInterval(fitnessTail)
            let candidate = HealthWorkoutCandidate(
                id: "fixture-fitness-workout",
                kind: .functionalStrength,
                start: fitnessStart,
                end: fitnessEnd,
                sourceName: "Eric's Apple Watch"
            )
            let duration = fitnessEnd.timeIntervalSince(fitnessStart)
            let count = 45
            let series = (0..<count).map { index -> HeartRatePoint in
                let progress = Double(index) / Double(count - 1)
                // Warm-up ramp, work/rest waves, a peak near the end, then a short cool-down.
                let ramp = 45 + 50 * min(1, progress * 4)
                let waves = 18 * sin(progress * 6 * .pi)
                let peak = 25 * max(0, 1 - abs(progress - 0.85) * 10)
                let cooldown = progress > 0.92 ? -(progress - 0.92) * 300 : 0
                let bpm = (ramp + waves + peak + cooldown).rounded()
                return HeartRatePoint(offset: progress * duration, bpm: min(max(bpm, 62), 161))
            }
            let summary = HealthWorkoutSummary(
                healthWorkoutID: candidate.id,
                start: fitnessStart,
                end: fitnessEnd,
                activeEnergyKcal: 310,
                totalEnergyKcal: 420,
                avgHeartRate: 118,
                maxHeartRate: 161,
                heartRateSeries: series,
                effort: HealthEffort(score: 8, isEstimated: false),
                zones: [
                    HeartRateZoneTime(index: 1, lowerBPM: nil, upperBPM: 138, seconds: 39 * 60 + 53),
                    HeartRateZoneTime(index: 2, lowerBPM: 139, upperBPM: 150, seconds: 2 * 60 + 30),
                    HeartRateZoneTime(index: 3, lowerBPM: 151, upperBPM: 162, seconds: 1 * 60 + 10),
                    HeartRateZoneTime(index: 4, lowerBPM: 163, upperBPM: 174, seconds: 0),
                    HeartRateZoneTime(index: 5, lowerBPM: 175, upperBPM: nil, seconds: 0),
                ],
                weatherTemperatureCelsius: 19,
                weatherHumidityPercent: 65,
                timeZoneIdentifier: "America/Toronto",
                details: HealthWorkoutDetails(
                    statistics: [
                        "HKQuantityTypeIdentifierActiveEnergyBurned": HealthStatistic(sum: 310, unit: "kcal"),
                        "HKQuantityTypeIdentifierHeartRate": HealthStatistic(
                            average: 118,
                            minimum: 62,
                            maximum: 161,
                            mostRecent: 96,
                            unit: "count/min"
                        ),
                    ],
                    metadata: [
                        "HKIndoorWorkout": "1",
                        "HKTimeZone": "America/Toronto",
                        "HKWeatherTemperature": "66.2 degF",
                    ],
                    sourceName: "Eric's Apple Watch",
                    sourceBundleID: "com.apple.health.fixture",
                    deviceName: "Apple Watch",
                    deviceModel: "Watch"
                )
            )
            return FakeHealthSource(candidates: [candidate], summaries: [summary])
        }
    }

    /// A `HealthSource` that builds a `HealthFixture` around whatever workout is being looked up.
    ///
    /// `HealthEnrichment` queries the workout's interval widened by the matcher's slack, so `workouts(in:)` narrows the
    /// query back to the workout and builds the fixture around that. `summary(for:)` receives the candidate it produced and
    /// rebuilds the same fixture from the candidate's own times. A query that is not slack-widened (shorter than the slack)
    /// is taken as the workout itself.
    private nonisolated struct HealthFixtureSource: HealthSource {
        let fixture: HealthFixture

        func workouts(in interval: DateInterval) async throws -> [HealthWorkoutCandidate] {
            let before = HealthMatcher.defaultSlackBefore
            let after = HealthMatcher.defaultSlackAfter
            let start = interval.start.addingTimeInterval(before)
            let end = interval.end.addingTimeInterval(-after)
            let ours = end > start ? (start, end) : (interval.start, interval.end)
            return try await fixture.source(around: ours.0, end: ours.1).workouts(in: interval)
        }

        func summary(for candidate: HealthWorkoutCandidate) async throws -> HealthWorkoutSummary {
            let start = candidate.start.addingTimeInterval(HealthFixture.fitnessLeadIn)
            let end = candidate.end.addingTimeInterval(-HealthFixture.fitnessTail)
            return try await fixture.source(around: start, end: end).summary(for: candidate)
        }
    }
#endif
