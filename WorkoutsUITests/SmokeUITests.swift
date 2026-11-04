import XCTest

/// The smoke flows: launch, the `-preview` gallery, and tab/Settings navigation.
final class SmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Every UI test launches with `-uiTesting`: an in-memory store, so no state is left over from earlier runs.
    @MainActor
    private func makeApp(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"] + extraArguments
        return app
    }

    @MainActor
    func testAppLaunches() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    @MainActor
    func testGallerySwatches() throws {
        let app = makeApp(["-preview", "Swatches"])
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["Accent"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testTabsAndSettings() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["screen.workout"].waitForExistence(timeout: 10))

        // Tab bar on compact width; the sidebar-adaptable bar keeps the same identifiers.
        let history = app.descendants(matching: .any)["tab.history"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        history.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.history"].waitForExistence(timeout: 5))

        let exercises = app.descendants(matching: .any)["tab.exercises"].firstMatch
        XCTAssertTrue(exercises.waitForExistence(timeout: 5))
        exercises.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.exercises"].waitForExistence(timeout: 5))

        app.descendants(matching: .any)["tab.workout"].firstMatch.tap()
        let settings = app.descendants(matching: .any)["toolbar.settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 5))

        let done = app.descendants(matching: .any)["settings.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.workout"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["screen.settings"].exists)
    }
}
