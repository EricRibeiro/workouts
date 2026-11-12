import XCTest

/// History's Apple Fitness lookup is a toolbar button ("Refresh Apple Fitness", only while Fitness is on); pulling the list
/// down does nothing. With Fitness opted in (`-healthEnrichmentEnabled YES`, the Settings toggle) and the
/// `-healthFixture full` source standing in for HealthKit, tapping the button enriches the sample workouts: History gains
/// active calories ("N active calories" on the week card and the rows), which nothing else does here (the gallery never
/// runs the launch or foreground lookup). With Fitness off the button does not exist. No Health store is touched.
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

    /// Presses near the top of the list and drags down, the way a finger pulls the list past its top.
    @MainActor
    private func pullDown(_ app: XCUIApplication) {
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), "no History list")
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = start.withOffset(CGVector(dx: 0, dy: 300))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    @MainActor
    func testRefreshButtonLooksUpFitnessWhileItIsOn() throws {
        let app = XCUIApplication.launchedPreview(
            "History",
            extraArguments: ["-healthFixture", "full", "-healthEnrichmentEnabled", "YES"],
            waitingFor: "screen.history"
        )
        XCTAssertEqual(calorieElements(app).count, 0, "calories before any lookup ran")
        let button = app.buttons["history.fitnessRefresh"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no Refresh Apple Fitness button")
        button.tap()
        let row = calorieElements(app).firstMatch
        for _ in 0..<6 where !row.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(row.exists, "the refresh button did not look up Apple Fitness")
    }

    @MainActor
    func testNoRefreshButtonWhileFitnessIsOff() throws {
        let app = XCUIApplication.launchedPreview(
            "History",
            extraArguments: ["-healthFixture", "full"],
            waitingFor: "screen.history"
        )
        app.buttons["history.fitnessRefresh"].assertStaysAbsent(for: 1.5, "a refresh button with Apple Fitness off")
    }

    @MainActor
    func testPullingDownDoesNothing() throws {
        let app = XCUIApplication.launchedPreview(
            "History",
            extraArguments: ["-healthFixture", "full", "-healthEnrichmentEnabled", "YES"],
            waitingFor: "screen.history"
        )
        pullDown(app)
        app.keyboards.firstMatch.assertStaysAbsent(for: 2, "pulling the list down opened search")
        app.otherElements["Refreshing content"].assertStaysAbsent(for: 1.5, "a refresh spinner after the pull")
        XCTAssertEqual(calorieElements(app).count, 0, "the pull looked up Apple Fitness")
    }
}
