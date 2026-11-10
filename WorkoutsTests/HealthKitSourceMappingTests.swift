import Foundation
import HealthKit
import Testing
import WorkoutsKit

@testable import Workouts

struct HealthKitSourceMappingTests {
    // MARK: map

    @Test(arguments: [HKError.Code.errorAuthorizationDenied, .errorAuthorizationNotDetermined])
    func authorizationErrorsMapToNotAuthorized(code: HKError.Code) {
        #expect(HealthKitSource.map(HKError(code)) == .notAuthorized)
    }

    @Test(arguments: [HKError.Code.errorHealthDataUnavailable, .errorHealthDataRestricted])
    func unavailableErrorsMapToUnavailable(code: HKError.Code) {
        #expect(HealthKitSource.map(HKError(code)) == .unavailable)
    }

    @Test func otherHealthKitErrorMapsToFailedWithItsDescription() {
        let error = HKError(.errorInvalidArgument)
        #expect(HealthKitSource.map(error) == .failed(error.localizedDescription))
    }

    @Test func nonHealthKitErrorMapsToFailedWithItsDescription() {
        let error = NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "boom"])
        #expect(HealthKitSource.map(error) == .failed("boom"))
    }

    @Test func sourceErrorPassesThrough() {
        #expect(HealthKitSource.map(HealthSourceError.notFound) == .notFound)
    }

    // MARK: kind(of:)

    @Test func strengthActivitiesMapToTheirKinds() {
        #expect(HealthKitSource.kind(of: .functionalStrengthTraining) == .functionalStrength)
        #expect(HealthKitSource.kind(of: .traditionalStrengthTraining) == .traditionalStrength)
    }

    @Test func otherActivityKeepsItsRawValueAsName() {
        let type = HKWorkoutActivityType.running
        #expect(HealthKitSource.kind(of: type) == .other("activity \(type.rawValue)"))
        #expect(HealthKitSource.kind(of: type).isStrength == false)
    }

    // MARK: quantity(_:in:)

    @Test func quantityReadsInTheRequestedUnit() {
        let metres = HKQuantity(unit: .meter(), doubleValue: 1500)
        #expect(HealthKitSource.quantity(metres, in: .meter()) == 1500)
        #expect(HealthKitSource.quantity(metres, in: .meterUnit(with: .kilo)) == 1.5)
    }

    @Test func quantityIsNilForAbsentWrongKindOrWrongDimension() {
        let metres = HKQuantity(unit: .meter(), doubleValue: 1)
        #expect(HealthKitSource.quantity(nil, in: .meter()) == nil)
        #expect(HealthKitSource.quantity("1", in: .meter()) == nil)
        #expect(HealthKitSource.quantity(metres, in: .kilocalorie()) == nil)
    }

    // MARK: text(_:)

    @Test func textDescribesEachMetadataKind() {
        let quantity = HKQuantity(unit: .meter(), doubleValue: 5)
        #expect(HealthKitSource.text(quantity) == quantity.description)
        #expect(HealthKitSource.text(Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00Z")
        #expect(HealthKitSource.text(42) == "42")
        #expect(HealthKitSource.text(1.5) == "1.5")
        #expect(HealthKitSource.text("indoor") == "indoor")
        #expect(HealthKitSource.text([1, 2]) == "[1, 2]")
    }

    // MARK: statisticUnit(for:)

    @Test(
        arguments: [
            (HKQuantityTypeIdentifier.activeEnergyBurned, "kcal"),
            (.heartRate, "count/min"),
            (.distanceWalkingRunning, "m"),
            (.walkingSpeed, "m/s"),
            (.cyclingPower, "W"),
            (.stepCount, "count"),
            (.appleExerciseTime, "s"),
            (.bodyTemperature, "degC"),
            (.oxygenSaturation, "%"),
            (.bloodAlcoholContent, "%"),
            (.walkingAsymmetryPercentage, "%"),
            (.walkingDoubleSupportPercentage, "%"),
            (.appleWalkingSteadiness, "%"),
            (.atrialFibrillationBurden, "%"),
        ]
    )
    func statisticUnitIsTheFirstCompatible(identifier: HKQuantityTypeIdentifier, name: String) {
        let match = HealthKitSource.statisticUnit(for: HKQuantityType(identifier))
        #expect(match?.name == name)
    }

    @Test func percentStatisticsAreReportedAsZeroTo100() throws {
        let value = try #require(HealthKitSource.statisticValue(0.97, unitName: "%"))
        #expect(abs(value - 97) < 1e-9)
        #expect(HealthKitSource.statisticValue(nil, unitName: "%") == nil)
        #expect(HealthKitSource.statisticValue(0.97, unitName: "count") == 0.97)
    }

    @Test func statisticUnitIsNilWhenNoneFits() {
        #expect(HealthKitSource.statisticUnit(for: HKQuantityType(.bodyMass)) == nil)
    }

    // MARK: derive and effort

    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func totalEnergyIsActivePlusBasal() {
        let fields = derive(active: 200, basal: 30)
        #expect(fields.totalEnergyKcal == 230)
    }

    @Test func totalEnergyFallsBackToWhicheverExists() {
        #expect(derive(active: 200, basal: nil).totalEnergyKcal == 200)
        #expect(derive(active: nil, basal: 30).totalEnergyKcal == 30)
        #expect(derive(active: nil, basal: nil).totalEnergyKcal == nil)
    }

    @Test func heartRateOffsetsAreSecondsFromStartFlooredAtZero() {
        let fields = derive(
            heartRate: [
                (start: start.addingTimeInterval(-5), bpm: 90),
                (start: start, bpm: 100),
                (start: start.addingTimeInterval(60), bpm: 140),
            ]
        )
        #expect(
            fields.heartRateSeries == [
                HeartRatePoint(offset: 0, bpm: 90),
                HeartRatePoint(offset: 0, bpm: 100),
                HeartRatePoint(offset: 60, bpm: 140),
            ]
        )
    }

    @Test func humidityFractionIsScaledAndPercentageIsKept() {
        #expect(derive(humidity: 0.83).humidityPercent == 83)
        #expect(derive(humidity: 83).humidityPercent == 83)
        #expect(derive(humidity: nil).humidityPercent == nil)
    }

    @Test func ratedEffortWinsOverEstimate() {
        #expect(HealthKitSource.effort(rated: 7, estimated: 5) == HealthEffort(score: 7, isEstimated: false))
        #expect(HealthKitSource.effort(rated: nil, estimated: 5) == HealthEffort(score: 5, isEstimated: true))
        #expect(HealthKitSource.effort(rated: nil, estimated: nil) == nil)
    }

    private func derive(
        active: Double? = nil,
        basal: Double? = nil,
        heartRate: [(start: Date, bpm: Double)] = [],
        humidity: Double? = nil
    ) -> HealthKitSource.DerivedFields {
        HealthKitSource.derive(
            active: active,
            basal: basal,
            workoutStart: start,
            heartRate: heartRate,
            humidityHealthPercent: humidity
        )
    }
}
