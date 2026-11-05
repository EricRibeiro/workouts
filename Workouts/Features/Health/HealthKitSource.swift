//
//  HealthKitSource.swift
//  Workouts
//

import CoreLocation
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

    /// The types read: workouts, heart rate, active and resting energy, the workout route and the effort scores. Every type
    /// the enrichment may ever use is requested up front, because adding one later prompts the person again.
    static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.basalEnergyBurned),
        HKSeriesType.workoutRoute(),
        HKQuantityType(.workoutEffortScore),
        HKQuantityType(.estimatedWorkoutEffortScore),
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
                heartRateSeries: series,
                effort: await effort(for: workout),
                zones: Self.zones(of: workout, bpm: bpm),
                weatherTemperatureCelsius: Self.quantity(
                    workout.metadata?[HKMetadataKeyWeatherTemperature],
                    in: .degreeCelsius()
                ),
                weatherHumidityPercent: Self.quantity(workout.metadata?[HKMetadataKeyWeatherHumidity], in: .percent())
                    .map { $0 * 100 },
                timeZoneIdentifier: workout.metadata?[HKMetadataKeyTimeZone] as? String,
                details: await details(for: workout)
            )
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Best-effort extras (PLAN 7.1b e4). A failing sub-query leaves its field nil or empty and never fails the summary.

    /// The workout's effort: a rated score wins over Apple's estimate.
    private func effort(for workout: HKWorkout) async -> HealthEffort? {
        let descriptor = HKWorkoutEffortRelationshipQueryDescriptor(
            predicate: HKQuery.predicateForObject(with: workout.uuid),
            anchor: nil,
            option: .default
        )
        guard let result = try? await descriptor.result(for: store) else { return nil }
        let samples = result.relationships.flatMap { $0.samples ?? [] }.compactMap { $0 as? HKQuantitySample }
        let unit = HKUnit.appleEffortScore()
        if let rated = samples.first(where: { $0.quantityType == HKQuantityType(.workoutEffortScore) }) {
            return HealthEffort(score: rated.quantity.doubleValue(for: unit), isEstimated: false)
        }
        if let estimated = samples.first(where: { $0.quantityType == HKQuantityType(.estimatedWorkoutEffortScore) }) {
            return HealthEffort(score: estimated.quantity.doubleValue(for: unit), isEstimated: true)
        }
        return nil
    }

    /// Time in each heart-rate zone, lowest effort first; empty when Health has no zones for the workout.
    private static func zones(of workout: HKWorkout, bpm: HKUnit) -> [HeartRateZoneTime] {
        guard let group = workout.zoneGroup(for: HKQuantityType(.heartRate)) else { return [] }
        return group.zoneDurations.map { entry in
            HeartRateZoneTime(
                index: entry.zone.index,
                lowerBPM: entry.zone.minimum?.doubleValue(for: bpm),
                upperBPM: entry.zone.maximum?.doubleValue(for: bpm),
                seconds: entry.duration
            )
        }
    }

    /// A metadata value that is an `HKQuantity`, in `unit`; nil when absent or of another kind or dimension.
    private static func quantity(_ value: Any?, in unit: HKUnit) -> Double? {
        guard let quantity = value as? HKQuantity, quantity.is(compatibleWith: unit) else { return nil }
        return quantity.doubleValue(for: unit)
    }

    /// Everything else HealthKit holds for the workout, as the kit's snapshot.
    private func details(for workout: HKWorkout) async -> HealthWorkoutDetails {
        var statistics: [String: HealthStatistic] = [:]
        for (type, value) in workout.allStatistics {
            if let statistic = Self.statistic(type, value) { statistics[type.identifier] = statistic }
        }
        var metadata: [String: String] = [:]
        for (key, value) in workout.metadata ?? [:] {
            metadata[key] = Self.text(value)
        }
        let device = workout.device
        return HealthWorkoutDetails(
            statistics: statistics,
            metadata: metadata,
            events: (workout.workoutEvents ?? []).map {
                HealthInterval(
                    type: "event \($0.type.rawValue)",
                    start: $0.dateInterval.start,
                    end: $0.dateInterval.end
                )
            },
            activities: workout.workoutActivities.map {
                HealthInterval(
                    type: "activity \($0.workoutConfiguration.activityType.rawValue)",
                    start: $0.startDate,
                    end: $0.endDate ?? workout.endDate
                )
            },
            sourceName: workout.sourceRevision.source.name,
            sourceBundleID: workout.sourceRevision.source.bundleIdentifier,
            deviceName: device?.name,
            deviceModel: device?.model,
            deviceHardwareVersion: device?.hardwareVersion,
            deviceSoftwareVersion: device?.softwareVersion,
            route: await route(for: workout)
        )
    }

    /// Points of every route associated with the workout, oldest first; empty when none or unreadable.
    private func route(for workout: HKWorkout) async -> [HealthRoutePoint] {
        let predicate = HKQuery.predicateForObjects(from: workout)
        let query = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await query.result(for: store) else { return [] }
        var points: [HealthRoutePoint] = []
        for case let route as HKWorkoutRoute in samples {
            do {
                for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store) {
                    points.append(
                        HealthRoutePoint(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude,
                            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                            timestamp: location.timestamp
                        )
                    )
                }
            } catch {
                continue
            }
        }
        return points
    }

    /// Units tried in order for a statistic; the first compatible with the type is used. Types none fits are skipped.
    private static let statisticUnits: [(name: String, unit: HKUnit)] = [
        ("kcal", .kilocalorie()),
        ("count/min", .count().unitDivided(by: .minute())),
        ("m", .meter()),
        ("m/s", .meter().unitDivided(by: .second())),
        ("W", .watt()),
        ("count", .count()),
        ("s", .second()),
        ("degC", .degreeCelsius()),
        ("%", .percent()),
    ]

    private static func statistic(_ type: HKQuantityType, _ statistics: HKStatistics) -> HealthStatistic? {
        guard let match = statisticUnits.first(where: { type.is(compatibleWith: $0.unit) }) else { return nil }
        let unit = match.unit
        let result = HealthStatistic(
            sum: statistics.sumQuantity()?.doubleValue(for: unit),
            average: statistics.averageQuantity()?.doubleValue(for: unit),
            minimum: statistics.minimumQuantity()?.doubleValue(for: unit),
            maximum: statistics.maximumQuantity()?.doubleValue(for: unit),
            mostRecent: statistics.mostRecentQuantity()?.doubleValue(for: unit),
            unit: match.name
        )
        let values = [result.sum, result.average, result.minimum, result.maximum, result.mostRecent]
        return values.contains { $0 != nil } ? result : nil
    }

    /// A metadata value as text: quantities by their description, dates as ISO 8601, numbers and strings as themselves.
    private static func text(_ value: Any) -> String {
        switch value {
        case let quantity as HKQuantity: quantity.description
        case let date as Date: date.formatted(.iso8601)
        case let number as NSNumber: number.stringValue
        case let string as String: string
        default: String(describing: value)
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
