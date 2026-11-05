import XCTest

/// The Health fixture path: `-healthFixture` feeds `HealthEnrichment` for the sample workout, and the finished-workout
/// detail (gallery entry `WorkoutDetail`) shows the result as stats in its header and the heart-rate chart card.
final class FitnessFixtureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(fixture: String) -> XCUIApplication {
        let app = XCUIApplication.launchedPreview("WorkoutDetail", extraArguments: ["-healthFixture", fixture])
        return app
    }

    @MainActor
    func testFullFixtureShowsHealthStatsAndChart() throws {
        let app = launch(fixture: "full")
        let any = app.descendants(matching: .any)
        let chart = any["workoutDetail.heartRate"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10), "no heart-rate chart")
        let header = any["workoutDetail.header"].firstMatch
        XCTAssertTrue(header.exists)
        let label = header.label
        XCTAssertTrue(label.contains("310 active calories"), "label was \(label)")
        XCTAssertTrue(label.contains("420 total calories"), "label was \(label)")
        XCTAssertTrue(label.contains("average heart rate 118"), "label was \(label)")
        XCTAssertTrue(label.contains("maximum heart rate 161"), "label was \(label)")
        XCTAssertTrue(label.contains("effort 8 Hard"), "label was \(label)")
        XCTAssertFalse(label.contains("estimated"), "label was \(label)")
        XCTAssertTrue(label.contains("weather"), "label was \(label)")
        let zones = any["heartRateChart.zones"].firstMatch
        XCTAssertTrue(zones.exists, "no zones under the chart")
        XCTAssertTrue(zones.label.contains("Zone 1"), "label was \(zones.label)")
        XCTAssertFalse(any["fitness.card"].exists, "the retired Fitness card is back")
    }

    @MainActor
    func testNoneFixtureShowsNoChartAndNoHealthStats() throws {
        let app = launch(fixture: "none")
        let any = app.descendants(matching: .any)
        let header = any["workoutDetail.header"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertFalse(
            any["workoutDetail.heartRate"].firstMatch.waitForExistence(timeout: 3),
            "chart with no Health data"
        )
        XCTAssertFalse(any["heartRateChart.zones"].exists)
        XCTAssertFalse(header.label.contains("heart rate"), "label was \(header.label)")
        XCTAssertFalse(header.label.contains("calories"), "label was \(header.label)")
    }

    @MainActor
    func testDeniedFixtureShowsNoChartAndNoHealthStats() throws {
        let app = launch(fixture: "denied")
        let any = app.descendants(matching: .any)
        let header = any["workoutDetail.header"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertFalse(
            any["workoutDetail.heartRate"].firstMatch.waitForExistence(timeout: 3),
            "chart with no Health data"
        )
        XCTAssertFalse(header.label.contains("calories"), "label was \(header.label)")
    }
}
