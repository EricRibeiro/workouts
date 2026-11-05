//
//  HealthSeeder.swift
//  Workouts
//

#if DEBUG
    import Foundation
    import HealthKit
    import OSLog
    import WorkoutsKit

    /// `-seedHealth`: writes one Functional Strength workout (last 50 minutes, ~300 kcal, ~40 heart-rate samples) into the
    /// simulator's Health store so the real `HealthKitSource` has something to read (docs/port/healthkit.md section 3).
    /// Everything it writes carries `metadataKey`, and earlier seeds are deleted first, so runs do not accumulate.
    /// Debug builds only: the app never writes to Health in Release.
    enum HealthSeeder {
        static let metadataKey = "WorkoutsDuoSeed"
        private static let logger = Logger(subsystem: "com.ericribeiro.Workouts", category: "HealthSeeder")

        static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-seedHealth") }

        /// Seeds when `-seedHealth` was passed. Fire and forget; the outcome is logged and printed.
        static func seedIfRequested() {
            guard isRequested, HealthKitSource.isAvailable else { return }
            Task {
                do {
                    let summary = try await seed()
                    print("HealthSeeder: saved \(summary)")
                    logger.notice("HealthSeeder: saved \(summary, privacy: .public)")
                } catch {
                    print("HealthSeeder: failed \(error)")
                    logger.error("HealthSeeder: failed \(String(describing: error), privacy: .public)")
                }
            }
        }

        private static func seed() async throws -> String {
            let store = HKHealthStore()
            let heartRateType = HKQuantityType(.heartRate)
            let energyType = HKQuantityType(.activeEnergyBurned)
            let workoutType = HKObjectType.workoutType()
            try await store.requestAuthorization(
                toShare: [workoutType, heartRateType, energyType],
                read: HealthKitSource.readTypes
            )

            let seeds = HKQuery.predicateForObjects(withMetadataKey: metadataKey)
            for type in [workoutType, heartRateType, energyType] as [HKObjectType] {
                _ = try await store.deleteObjects(of: type, predicate: seeds)
            }

            let end = Date.now
            let start = end.addingTimeInterval(-50 * 60)
            let metadata: [String: Any] = [metadataKey: true]
            let bpm = HKUnit.count().unitDivided(by: .minute())

            let heartRate: [HKQuantitySample] = (0..<40).map { index in
                let fraction = Double(index) / 39
                let at = start.addingTimeInterval(60 + fraction * 47 * 60)
                // A rolling profile, clamped to 90...160 bpm.
                let value = 125 + 35 * sin(fraction * 6 * .pi) * (0.4 + 0.6 * fraction)
                return HKQuantitySample(
                    type: heartRateType,
                    quantity: HKQuantity(unit: bpm, doubleValue: min(160, max(90, value.rounded()))),
                    start: at,
                    end: at,
                    metadata: metadata
                )
            }
            let energy: [HKQuantitySample] = (0..<6).map { index in
                let at = start.addingTimeInterval(Double(index) * 8 * 60)
                return HKQuantitySample(
                    type: energyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: 50),
                    start: at,
                    end: at.addingTimeInterval(8 * 60),
                    metadata: metadata
                )
            }

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .functionalStrengthTraining
            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
            try await builder.beginCollection(at: start)
            try await builder.addMetadata(metadata)
            try await builder.addSamples(heartRate + energy)
            try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else {
                throw HealthSourceError.failed("finishWorkout returned nil")
            }
            return
                "workout \(workout.uuid.uuidString), \(Int(workout.duration)) s, \(heartRate.count) heart-rate samples, 300 kcal"
        }
    }
#endif
