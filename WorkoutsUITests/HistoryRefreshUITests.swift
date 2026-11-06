import XCTest

/// Pull to refresh on History forces an Apple Fitness lookup now. With Fitness opted in (`-healthEnrichmentEnabled YES`,
/// the Settings toggle) and the `-healthFixture full` source standing in for HealthKit, dragging the list down enriches the
/// sample workouts: History gains active calories ("N active calories" on the week card and the rows), which nothing else does here (the gallery never
/// runs the launch or foreground lookup). With Fitness off the list has no refresh control, so the same drag changes
/// nothing. No Health store is touched.
///
/// The system spinner is visible to XCUITest (an element labelled "Refreshing content" in the navigation bar, not an
/// activity indicator), but it cannot be asserted live: `press(forDuration:thenDragTo:)` does not return until the app is
/// idle, and the spinning control keeps it busy until the refresh ends, so a refresh that finishes inside the call is over
/// by the time the call returns. The test therefore asserts the refresh's effect, and that the spinner is gone afterwards.
final class HistoryRefreshUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Anything on screen whose label carries Fitness calories: the week card on top of History says "N active calories"
    /// once a workout has them (so do the rows below it).
    @MainActor
    private func calorieElements(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'active calories'"))
    }

    /// Presses near the top of the list and drags down, the way a finger pulls the list to refresh.
    @MainActor
    private func pullToRefresh(_ app: XCUIApplication) {
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), "no History list")
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = start.withOffset(CGVector(dx: 0, dy: 300))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    @MainActor
    func testPullingDownLooksUpFitnessWhileItIsOn() throws {
        let app = XCUIApplication.launchedPreview(
            "History",
            extraArguments: ["-healthFixture", "full", "-healthEnrichmentEnabled", "YES"],
            waitingFor: "screen.history"
        )
        XCTAssertEqual(calorieElements(app).count, 0, "calories before any lookup ran")
        pullToRefresh(app)
        let row = calorieElements(app).firstMatch
        for _ in 0..<6 where !row.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(row.exists, "pulling the list down did not look up Apple Fitness")
        XCTAssertTrue(
            app.otherElements["Refreshing content"].waitForNonExistence(timeout: 15),
            "the refresh spinner never went away"
        )
    }

    @MainActor
    func testPullingDownDoesNothingWhileFitnessIsOff() throws {
        let app = XCUIApplication.launchedPreview(
            "History",
            extraArguments: ["-healthFixture", "full"],
            waitingFor: "screen.history"
        )
        pullToRefresh(app)
        XCTAssertFalse(app.otherElements["Refreshing content"].exists, "a refresh spinner with Apple Fitness off")
        // Same search as the opted-in test, so a miss here means the lookup did not run, not that it was not looked for.
        let row = calorieElements(app).firstMatch
        for _ in 0..<6 where !row.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertFalse(row.exists, "a lookup ran with Apple Fitness off")
    }
}
