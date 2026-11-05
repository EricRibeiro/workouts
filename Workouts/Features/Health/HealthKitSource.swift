//
//  HealthKitSource.swift
//  Workouts
//

import Foundation
import HealthKit
import WorkoutsKit

/// The real `HealthSource`: reads Fitness workouts, energy and heart rate from HealthKit. Read-only; the app never writes
/// to Health (the DEBUG-only `HealthSeeder` is the one exception). This is the only file in the app that imports HealthKit,
/// and the kit never does.
nonisolated final class HealthKitSource: HealthSource {
    private let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    /// False on devices without Health (iPad, Mac, restricted).
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// The types read: workouts, heart rate, active and resting energy.
    static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.basalEnergyBurned),
    ]

    /// Shows the Health read sheet when the person has not answered yet; returns once it is dismissed. A denied read is not
    /// an error here (Health never reveals read denial); it shows up later as "no data".
    func requestReadAuthorization() async throws {
        guard Self.isAvailable else { throw HealthSourceError.unavailable }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
        } catch {
            throw Self.map(error)
        }
    }

    func workouts(in interval: DateInterval) async throws -> [HealthWorkoutCandidate] {
        guard Self.isAvailable else { throw HealthSourceError.unavailable }
        let window = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(window)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 25
        )
        do {
            return try await descriptor.result(for: store).map(Self.candidate)
        } catch {
            throw Self.map(error)
        }
    }

    func summary(for candidate: HealthWorkoutCandidate) async throws -> HealthWorkoutSummary {
        guard Self.isAvailable else { throw HealthSourceError.unavailable }
        guard let uuid = UUID(uuidString: candidate.id) else { throw HealthSourceError.notFound }
        do {
            let workoutQuery = HKSampleQueryDescriptor(
                predicates: [.workout(HKQuery.predicateForObject(with: uuid))],
                sortDescriptors: [],
                limit: 1
            )
            guard let workout = try await workoutQuery.result(for: store).first else {
                throw HealthSourceError.notFound
            }

            let active = Self.sum(workout, .activeEnergyBurned, unit: .kilocalorie())
            let basal = Self.sum(workout, .basalEnergyBurned, unit: .kilocalorie())
            let total = active.map { $0 + (basal ?? 0) } ?? basal

            let bpm = HKUnit.count().unitDivided(by: .minute())
            let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
            let samples = try await heartRateSamples(for: workout)
            let series = samples.map {
                HeartRatePoint(
                    offset: max(0, $0.startDate.timeIntervalSince(workout.startDate)),
                    bpm: $0.quantity.doubleValue(for: bpm)
                )
            }
            // The series stays raw: `HealthEnrichment.enrich` downsamples it.
            return HealthWorkoutSummary(
                healthWorkoutID: candidate.id,
                start: workout.startDate,
                end: workout.endDate,
                activeEnergyKcal: active,
                totalEnergyKcal: total,
                avgHeartRate: heartRate?.averageQuantity()?.doubleValue(for: bpm),
                maxHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: bpm),
                heartRateSeries: series
            )
        } catch {
            throw Self.map(error)
        }
    }

    /// Heart-rate samples recorded during the workout, oldest first. The time window also catches samples the Watch
    /// recorded without associating them with the workout.
    private func heartRateSamples(for workout: HKWorkout) async throws -> [HKQuantitySample] {
        let window = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: window)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store)
    }

    private static func sum(_ workout: HKWorkout, _ identifier: HKQuantityTypeIdentifier, unit: HKUnit) -> Double? {
        workout.statistics(for: HKQuantityType(identifier))?.sumQuantity()?.doubleValue(for: unit)
    }

    private static func candidate(_ workout: HKWorkout) -> HealthWorkoutCandidate {
        HealthWorkoutCandidate(
            id: workout.uuid.uuidString,
            kind: kind(of: workout.workoutActivityType),
            start: workout.startDate,
            end: workout.endDate,
            sourceName: workout.sourceRevision.source.name
        )
    }

    private static func kind(of type: HKWorkoutActivityType) -> HealthActivityKind {
        switch type {
        case .functionalStrengthTraining: .functionalStrength
        case .traditionalStrengthTraining: .traditionalStrength
        default: .other("activity \(type.rawValue)")
        }
    }

    /// HealthKit errors to the kit's: denied or undetermined authorization, unavailable data, anything else.
    static func map(_ error: any Error) -> HealthSourceError {
        if let known = error as? HealthSourceError { return known }
        if let hkError = error as? HKError {
            switch hkError.code {
            case .errorAuthorizationDenied, .errorAuthorizationNotDetermined:
                return .notAuthorized
            case .errorHealthDataUnavailable, .errorHealthDataRestricted:
                return .unavailable
            default:
                break
            }
        }
        return .failed(error.localizedDescription)
    }
}
