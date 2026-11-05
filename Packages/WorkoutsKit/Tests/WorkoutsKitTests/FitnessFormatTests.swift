import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct FitnessFormatTests {
    private static let us = Locale(identifier: "en_US")
    private static let britain = Locale(identifier: "en_GB")

    // MARK: Effort

    @Test func effortWordsFollowAppleScale() {
        let expected: [(Double, String)] = [
            (1, "Easy"), (3, "Easy"), (4, "Moderate"), (6, "Moderate"),
            (7, "Hard"), (8, "Hard"), (9, "All Out"), (10, "All Out"),
        ]
        for (score, word) in expected {
            #expect(HealthEffort(score: score, isEstimated: false).word == word, "score \(score)")
        }
    }

    @Test func effortRoundsAndClamps() {
        #expect(HealthEffort(score: 6.6, isEstimated: false).word == "Hard")
        #expect(HealthEffort(score: 3.4, isEstimated: false).word == "Easy")
        #expect(HealthEffort(score: 0, isEstimated: false).text == "1 Easy")
        #expect(HealthEffort(score: 14, isEstimated: false).text == "10 All Out")
    }

    @Test func effortTextMarksEstimates() {
        #expect(HealthEffort(score: 8, isEstimated: false).text == "8 Hard")
        #expect(HealthEffort(score: 8, isEstimated: true).text == "8 Hard · Estimated")
    }

    // MARK: Numbers

    @Test func kcalTextGroupsThousands() {
        #expect(FitnessFormat.kcalText(266.4) == "266 kcal")
        #expect(FitnessFormat.kcalText(1239.6) == "1,240 kcal")
        #expect(FitnessFormat.wholeNumber(118.5) == "119")
    }

    // MARK: Zones

    @Test func zoneSentenceSpellsTheTimeOut() {
        let zone = HeartRateZoneTime(index: 1, upperBPM: 138, seconds: 39 * 60 + 53)
        #expect(FitnessFormat.zoneSentence(zone) == "Zone 1, 39 minutes, 53 seconds, up to 138 bpm")
        #expect(FitnessFormat.spokenDuration(seconds: 0) == "0 seconds")
        #expect(FitnessFormat.spokenDuration(seconds: 3720) == "1 hour, 2 minutes")
    }

    @Test func zoneSharesAreFractionsOfTheTotal() {
        let zones = [
            HeartRateZoneTime(index: 1, seconds: 300),
            HeartRateZoneTime(index: 2, seconds: 100),
            HeartRateZoneTime(index: 3, seconds: 0),
        ]
        #expect(FitnessFormat.zoneShares(zones) == [0.75, 0.25, 0])
    }

    @Test func zoneSharesWithNoTimeAreZero() {
        #expect(FitnessFormat.zoneShares([HeartRateZoneTime(index: 1, seconds: 0)]) == [0])
        #expect(FitnessFormat.zoneShares([]).isEmpty)
    }

    @Test func zoneRangeTextCoversOpenEnds() {
        #expect(FitnessFormat.zoneRangeText(HeartRateZoneTime(index: 1, upperBPM: 138, seconds: 1)) == "up to 138 bpm")
        #expect(
            FitnessFormat.zoneRangeText(HeartRateZoneTime(index: 2, lowerBPM: 139, upperBPM: 150, seconds: 1))
                == "139\u{2013}150 bpm"
        )
        #expect(FitnessFormat.zoneRangeText(HeartRateZoneTime(index: 5, lowerBPM: 175, seconds: 1)) == "175+ bpm")
        #expect(FitnessFormat.zoneRangeText(HeartRateZoneTime(index: 1, seconds: 1)) == nil)
    }

    // MARK: Weather

    @Test func temperatureUsesTheLocalesWeatherUnit() {
        #expect(FitnessFormat.temperatureText(celsius: 19, locale: Self.us) == "66°F")
        #expect(FitnessFormat.temperatureText(celsius: 19, locale: Self.britain) == "19°C")
    }

    @Test func humidityPercentNormalisesFractionsAndPercentages() {
        #expect(abs(FitnessFormat.humidityPercent(fromHealthPercent: 0.65) - 65) < 1e-9)
        #expect(FitnessFormat.humidityPercent(fromHealthPercent: 83) == 83)
        #expect(FitnessFormat.humidityPercent(fromHealthPercent: 1) == 100)
        #expect(FitnessFormat.humidityPercent(fromHealthPercent: 0) == 0)
    }

    @Test func humidityTextRepairsValuesStoredTimesOneHundred() {
        #expect(FitnessFormat.humidityText(percent: 83, locale: Self.us) == "83%")
        #expect(FitnessFormat.humidityText(percent: 8300, locale: Self.us) == "83%")
        #expect(FitnessFormat.humidityText(percent: 100, locale: Self.us) == "100%")
    }

    @Test func weatherTextJoinsWhatExists() {
        #expect(
            FitnessFormat.weatherText(celsius: 19, humidityPercent: 65, locale: Self.britain) == "19°C, 65% humidity"
        )
        #expect(FitnessFormat.weatherText(celsius: nil, humidityPercent: 40, locale: Self.us) == "40% humidity")
        #expect(FitnessFormat.weatherText(celsius: 0, humidityPercent: nil, locale: Self.britain) == "0°C")
        #expect(FitnessFormat.weatherText(celsius: nil, humidityPercent: nil) == nil)
    }

    // MARK: History row and dashboard

    @Test func historyLabelAddsActiveCalories() {
        let entry = HistoryEntry(
            id: UUID(),
            name: "Push",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationSeconds: 3600,
            volume: 100,
            unit: .kg,
            prCount: 0,
            exerciseNames: []
        )
        let plain = HistoryList.accessibilityLabel(for: entry)
        #expect(!plain.contains("calories"))
        #expect(HistoryList.accessibilityLabel(for: entry, activeKcal: 266.2) == plain + ", 266 active calories")
    }

    @MainActor
    @Test func weekActiveCaloriesSumsTheWeekAndHidesWhenNone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto") ?? .gmt
        func day(_ d: Int, _ h: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h)) ?? .distantPast
        }
        let context = ModelContext(try ModelContainer.workouts(inMemory: true, cloudKit: false))
        func workout(_ start: Date, kcal: Double?, finished: Bool = true) -> Workout {
            let workout = Workout(
                name: "w",
                startedAt: start,
                finishedAt: finished ? start.addingTimeInterval(3000) : nil
            )
            workout.activeEnergyKcal = kcal
            context.insert(workout)
            return workout
        }
        // Tue Nov 3 is "now"; the week is Mon Nov 2 to Sun Nov 8.
        let now = day(3)
        let none = [workout(day(3), kcal: nil), workout(day(1, 23), kcal: 500)]
        #expect(HistoryDashboard.weekActiveCalories(workouts: none, calendar: calendar, now: now) == nil)
        let some =
            none + [
                workout(day(2, 8), kcal: 200), workout(day(3, 9), kcal: 150.5),
                workout(day(4), kcal: 90, finished: false),
            ]
        #expect(HistoryDashboard.weekActiveCalories(workouts: some, calendar: calendar, now: now) == 350.5)
    }
}
