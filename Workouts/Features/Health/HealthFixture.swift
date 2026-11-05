//
//  HealthFixture.swift
//  Workouts
//

#if DEBUG
    import Foundation
    import WorkoutsKit

    /// Canned Health data for previews, the gallery and UI tests (`-healthFixture <name>`), so the enrichment path is provable
    /// without HealthKit or a paired watch.
    enum HealthFixture: String, CaseIterable {
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
            let fitnessStart = start.addingTimeInterval(-45)
            let fitnessEnd = end.addingTimeInterval(30)
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
                heartRateSeries: series
            )
            return FakeHealthSource(candidates: [candidate], summaries: [summary])
        }
    }
#endif
