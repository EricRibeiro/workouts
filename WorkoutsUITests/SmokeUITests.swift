import XCTest

/// The smoke flows: launch, the `-preview` gallery, and tab/Settings navigation.
final class SmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Every UI test launches with `-uiTesting`: an in-memory store, so no state is left over from earlier runs.
    @MainActor
    private func makeApp(_ extraArguments: [String] = []) -> XCUIApplication {
        XCUIApplication.launchedForTesting(extraArguments)
    }

    @MainActor
    func testAppLaunches() throws {
        let app = makeApp()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    @MainActor
    func testGallerySwatches() throws {
        let app = makeApp(["-preview", "Swatches"])
        XCTAssertTrue(app.descendants(matching: .any)["Accent"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testTabsAndSettings() throws {
        let app = makeApp()

        XCTAssertTrue(app.descendants(matching: .any)["screen.workout"].waitForExistence(timeout: 10))

        // The system tab bar (the trailing strip on the closed Duo).
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
        XCTAssertTrue(
            app.descendants(matching: .any)["screen.settings"].waitUntilGone(timeout: 5),
            "Settings is still up after Done"
        )
    }

    /// JC52: the tab bar is the three main tabs and nothing else (no app sidebar, no template tabs), sample templates or not.
    @MainActor
    func testTabBarHasOnlyTheThreeTabs() throws {
        let app = makeApp(["-seedSampleData"])
        XCTAssertTrue(app.descendants(matching: .any)["screen.workout"].waitForExistence(timeout: 10))
        // Template cards are on screen, so the seed is in.
        XCTAssertTrue(app.descendants(matching: .any)["workout.list"].waitForExistence(timeout: 5))
        for id in ["tab.history", "tab.workout", "tab.exercises"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].firstMatch.waitForExistence(timeout: 5), id)
        }
        let leaked = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'sidebar.'"))
        XCTAssertEqual(leaked.count, 0)
    }
}
