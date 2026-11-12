import XCTest

/// Closing a screen's search with its x leaves it closed. Runs in the real tab shell (the `-preview` gallery places search
/// differently) and in whatever pose the simulator is in; the open-pose regression is in `OpenPoseUITests`.
final class SearchCloseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHistorySearchClosesAndStaysClosed() throws {
        let app = XCUIApplication.launchedForTesting(["-sampleWorkouts", "40"])
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(app.descendants(matching: .any)["screen.history"].waitForExistence(timeout: 10))
        app.assertSearchClosesAndStaysClosed()
    }

    @MainActor
    func testHistorySearchClosesAndStaysClosedWithFitnessOn() throws {
        let app = XCUIApplication.launchedForTesting([
            "-sampleWorkouts", "40", "-healthFixture", "full", "-healthEnrichmentEnabled", "YES",
        ])
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(app.descendants(matching: .any)["screen.history"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["history.fitnessRefresh"].waitForExistence(timeout: 10), "no Fitness refresh button")
        app.assertSearchClosesAndStaysClosed()
    }

    @MainActor
    func testExercisesSearchClosesAndStaysClosed() throws {
        let app = XCUIApplication.launchedForTesting(["-sampleWorkouts", "40"])
        app.selectTab("tab.exercises", label: "Exercises")
        XCTAssertTrue(app.descendants(matching: .any)["screen.exercises"].waitForExistence(timeout: 10))
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'exercises.row.'")
        )
        .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no exercise row")
        app.assertSearchClosesAndStaysClosed()
    }
}
