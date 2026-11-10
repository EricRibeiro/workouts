//
//  HealthHistorySeeder.swift
//  Workouts
//

#if DEBUG
    import CoreLocation
    import Foundation
    import HealthKit
    import OSLog
    import WorkoutsKit

    /// `-seedHealthHistory <days>` (default 200, clamped 1...400): fills the simulator's Health store with daily activity
    /// samples, weekly VO2 max and a weekday workout routine, so Apple's Fitness app has months of history to show.
    /// Everything carries `metadataKey` and earlier runs are deleted first, so reruns do not accumulate. Deterministic.
    enum HealthHistorySeeder {
        static let metadataKey = "WorkoutsDuoSeedHistory"
        private static let logger = Logger(subsystem: "com.ericribeiro.Workouts", category: "HealthHistorySeeder")
        private static let flag = "-seedHealthHistory"

        static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(flag) }

        /// The running seed, set by `seedIfRequested`.
        static var seeding: Task<Void, Never>?

        static func seedIfRequested() {
            guard isRequested, HealthKitSource.isAvailable else { return }
            let arguments = ProcessInfo.processInfo.arguments
            let days = arguments.firstIndex(of: flag).flatMap { index in
                arguments.indices.contains(index + 1) ? Int(arguments[index + 1]) : nil
            }
            seeding = Task {
                do {
                    let summary = try await seed(days: min(400, max(1, days ?? 200)))
                    report("HealthHistorySeeder: done \(summary.workouts) workouts, \(summary.samples) samples")
                } catch {
                    report("HealthHistorySeeder: failed \(error)")
                }
            }
        }

        fileprivate static func report(_ line: String) {
            print(line)
            logger.notice("\(line, privacy: .public)")
        }

        private static func seed(days: Int) async throws -> (workouts: Int, samples: Int) {
            let store = HKHealthStore()
            let workoutType = HKObjectType.workoutType()
            let routeType = HKSeriesType.workoutRoute()
            let quantityTypes: [HKQuantityType] = [
                HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned),
                HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling),
                HKQuantityType(.vo2Max), HKQuantityType(.workoutEffortScore),
            ]
            let writtenTypes: [HKSampleType] = [workoutType, routeType] + quantityTypes
            try await store.requestAuthorization(toShare: Set(writtenTypes), read: HealthKitSource.readTypes)

            let seeds = HKQuery.predicateForObjects(withMetadataKey: metadataKey)
            for type in writtenTypes as [HKObjectType] {
                _ = try await store.deleteObjects(of: type, predicate: seeds)
            }

            var run = Run(store: store)
            let today = run.calendar.startOfDay(for: .now)
            for (done, offset) in (0..<days).reversed().enumerated() {
                guard let day = run.calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                try await run.seedDay(day, isWeekStart: offset % 7 == 0)
                if (done + 1) % 30 == 0 { report("HealthHistorySeeder: \(done + 1)/\(days) days done") }
            }
            return (run.workouts, run.samples)
        }
    }

    /// One workout kind of the weekly routine.
    private struct WorkoutPlan {
        let activity: HKWorkoutActivityType
        let indoor: Bool
        let minutes: ClosedRange<Double>
        let kcal: ClosedRange<Double>
        let kilometers: ClosedRange<Double>?
        let effort: ClosedRange<Double>
        let heartRate: ClosedRange<Double>
        let startHour: Int

        /// Mon...Sun = weekday 2...7, 1; nil on Thursday (rest).
        static func forWeekday(_ weekday: Int) -> WorkoutPlan? {
            switch weekday {
            case 2, 4, 6:
                WorkoutPlan(
                    activity: .functionalStrengthTraining,
                    indoor: true,
                    minutes: 45...65,
                    kcal: 250...350,
                    kilometers: nil,
                    effort: 6...9,
                    heartRate: 105...150,
                    startHour: 18
                )
            case 3:
                WorkoutPlan(
                    activity: .cycling,
                    indoor: true,
                    minutes: 30...40,
                    kcal: 170...240,
                    kilometers: 10...14,
                    effort: 3...5,
                    heartRate: 115...160,
                    startHour: 18
                )
            case 7:
                WorkoutPlan(
                    activity: .running,
                    indoor: false,
                    minutes: 25...40,
                    kcal: 300...450,
                    kilometers: 4...6,
                    effort: 6...8,
                    heartRate: 140...175,
                    startHour: 9
                )
            case 1:
                WorkoutPlan(
                    activity: .walking,
                    indoor: false,
                    minutes: 30...50,
                    kcal: 120...200,
                    kilometers: 2...4,
                    effort: 2...3,
                    heartRate: 95...120,
                    startHour: 9
                )
            default:
                nil
            }
        }
    }

    private struct Run {
        let store: HKHealthStore
        let calendar = Calendar.current
        var generator = SeededGenerator(seed: 0x5EED_4EA1_7415)
        var workouts = 0
        var samples = 0

        private let seedKey = HealthHistorySeeder.metadataKey
        private let bpm = HKUnit.count().unitDivided(by: .minute())

        init(store: HKHealthStore) { self.store = store }

        mutating func seedDay(_ day: Date, isWeekStart: Bool) async throws {
            var batch = daySamples(day)
            if isWeekStart {
                let at = min(day.addingTimeInterval(8 * 3600), .now)
                let vo2 = Double.random(in: 37...40, using: &generator)
                batch.append(
                    quantity(.vo2Max, HKUnit(from: "ml/kg*min"), vo2.rounded(toPlaces: 1), at, at)
                )
            }
            try await store.save(batch)
            samples += batch.count

            // Every draw happens before the "is it in the future" check, so a rerun on another day reproduces the same history.
            let skipped = Double.random(in: 0..<1, using: &generator) < 0.15
            guard let plan = WorkoutPlan.forWeekday(calendar.component(.weekday, from: day)) else { return }
            let minutes = Double.random(in: plan.minutes, using: &generator).rounded()
            let kcal = Double.random(in: plan.kcal, using: &generator).rounded()
            let kilometers = plan.kilometers.map { Double.random(in: $0, using: &generator) }
            let effort = Double.random(in: plan.effort, using: &generator).rounded()
            guard !skipped, let start = calendar.date(byAdding: .hour, value: plan.startHour, to: day),
                start.addingTimeInterval(minutes * 60) <= .now
            else { return }
            try await seedWorkout(
                plan,
                start: start,
                minutes: minutes,
                kcal: kcal,
                meters: kilometers.map { $0 * 1000 },
                effort: effort
            )
        }

        // MARK: Daily activity

        private mutating func daySamples(_ day: Date) -> [HKQuantitySample] {
            let hours = Array(7..<21)
            let weights = hours.map { _ in Double.random(in: 0.3...1.7, using: &generator) }
            let dayTotal = Double.random(in: 4_000...11_000, using: &generator)
            var batch: [HKQuantitySample] = []
            for (hour, weight) in zip(hours, weights) {
                guard let start = calendar.date(byAdding: .hour, value: hour, to: day) else { continue }
                let end = start.addingTimeInterval(3600)
                guard end <= .now else { continue }
                let steps = (dayTotal * weight / weights.reduce(0, +)).rounded()
                batch.append(quantity(.stepCount, .count(), steps, start, end))
                batch.append(quantity(.distanceWalkingRunning, .meter(), steps * 0.75, start, end))
                batch.append(quantity(.activeEnergyBurned, .kilocalorie(), steps * 0.04, start, end))
            }
            let basalEnd = min(day.addingTimeInterval(24 * 3600 - 60), .now)
            if basalEnd > day { batch.append(quantity(.basalEnergyBurned, .kilocalorie(), 1_700, day, basalEnd)) }
            return batch
        }

        // MARK: Workouts

        private mutating func seedWorkout(
            _ plan: WorkoutPlan,
            start: Date,
            minutes: Double,
            kcal: Double,
            meters: Double?,
            effort: Double
        ) async throws {
            let end = start.addingTimeInterval(minutes * 60)
            let seed: [String: Any] = [seedKey: true]
            var metadata = seed
            metadata[HKMetadataKeyIndoorWorkout] = plan.indoor
            metadata[HKMetadataKeyTimeZone] = calendar.timeZone.identifier

            var parts = heartRateSamples(plan, start: start, minutes: Int(minutes))
            parts += slices(.activeEnergyBurned, .kilocalorie(), total: kcal, start: start, minutes: minutes)
            if let meters {
                let cycling = plan.activity == .cycling
                parts += slices(
                    cycling ? .distanceCycling : .distanceWalkingRunning,
                    .meter(),
                    total: meters,
                    start: start,
                    minutes: minutes
                )
            }

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = plan.activity
            configuration.locationType = plan.indoor ? .indoor : .outdoor
            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
            try await builder.beginCollection(at: start)
            try await builder.addMetadata(metadata)
            try await builder.addSamples(parts)
            try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else {
                throw HealthSourceError.failed("finishWorkout returned nil")
            }
            let rating = HKQuantitySample(
                type: HKQuantityType(.workoutEffortScore),
                quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: effort),
                start: start,
                end: end,
                metadata: seed
            )
            try await store.save(rating)
            try await store.relateWorkoutEffortSample(rating, with: workout, activity: nil)
            workouts += 1
            samples += parts.count + 1

            if !plan.indoor, let meters {
                try await insertRoute(for: workout, start: start, minutes: minutes, meters: meters)
            }
        }

        /// One sample a minute: a warm-up ramp to the top of the plan's range, a slow wobble and some noise.
        private mutating func heartRateSamples(_ plan: WorkoutPlan, start: Date, minutes: Int) -> [HKQuantitySample] {
            (0..<minutes).map { minute in
                let fraction = Double(minute) / Double(max(1, minutes - 1))
                let ramp = min(1, fraction * 5)
                let wobble = 0.5 + 0.5 * sin(fraction * 5 * .pi)
                let level =
                    plan.heartRate.lowerBound + (plan.heartRate.upperBound - plan.heartRate.lowerBound) * ramp
                    * (0.6 + 0.4 * wobble)
                let value = min(175, max(90, level + Double.random(in: -4...4, using: &generator))).rounded()
                let at = start.addingTimeInterval(Double(minute) * 60 + 30)
                return quantity(.heartRate, bpm, value, at, at)
            }
        }

        /// 5-minute slices that sum exactly to `total`, each a jittered share of it by length.
        private mutating func slices(
            _ identifier: HKQuantityTypeIdentifier,
            _ unit: HKUnit,
            total: Double,
            start: Date,
            minutes: Double
        ) -> [HKQuantitySample] {
            let spans = stride(from: 0.0, to: minutes, by: 5).map { (from: $0, to: min(minutes, $0 + 5)) }
            let weights = spans.map { ($0.to - $0.from) * Double.random(in: 0.8...1.2, using: &generator) }
            let sum = weights.reduce(0, +)
            return zip(spans, weights).map { span, weight in
                quantity(
                    identifier,
                    unit,
                    total * weight / sum,
                    start.addingTimeInterval(span.from * 60),
                    start.addingTimeInterval(span.to * 60)
                )
            }
        }

        /// A loop whose circumference equals the distance, one fix every 5 s, finished onto `workout`.
        private func insertRoute(for workout: HKWorkout, start: Date, minutes: Double, meters: Double) async throws {
            let center = (latitude: 43.6465, longitude: -79.4637)
            let radius = meters / (2 * .pi)
            let metersPerDegree = 111_320.0
            let duration = minutes * 60
            let fixes = Int(duration / 5)
            let locations = (0...fixes).map { index -> CLLocation in
                let fraction = Double(index) / Double(fixes)
                let angle = fraction * 2 * .pi
                let coordinate = CLLocationCoordinate2D(
                    latitude: center.latitude + radius * sin(angle) / metersPerDegree,
                    longitude: center.longitude + radius * cos(angle)
                        / (metersPerDegree * cos(center.latitude * .pi / 180))
                )
                return CLLocation(
                    coordinate: coordinate,
                    altitude: 76,
                    horizontalAccuracy: 5,
                    verticalAccuracy: 5,
                    course: -1,
                    speed: meters / duration,
                    timestamp: start.addingTimeInterval(fraction * duration)
                )
            }
            let builder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
            try await builder.insertRouteData(locations)
            _ = try await builder.finishRoute(with: workout, metadata: [seedKey: true])
        }

        private func quantity(
            _ identifier: HKQuantityTypeIdentifier,
            _ unit: HKUnit,
            _ value: Double,
            _ start: Date,
            _ end: Date
        ) -> HKQuantitySample {
            HKQuantitySample(
                type: HKQuantityType(identifier),
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: start,
                end: end,
                metadata: [seedKey: true]
            )
        }
    }

    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        /// SplitMix64.
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    extension Double {
        fileprivate func rounded(toPlaces places: Int) -> Double {
            let factor = pow(10, Double(places))
            return (self * factor).rounded() / factor
        }
    }
#endif
