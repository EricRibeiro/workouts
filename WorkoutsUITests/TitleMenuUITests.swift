import XCTest

/// The logging screen's title menu (task 2.8 part 2): Rename… edits the workout name through an alert; Discard Workout
/// asks for confirmation and, once confirmed, closes the cover and returns to the Workout tab.
final class TitleMenuUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchCover() -> XCUIApplication {
        let app = XCUIApplication.launchedInActiveWorkout()
        return app
    }

    /// Opens the menu attached to the navigation title.
    @MainActor
    private func openTitleMenu(_ app: XCUIApplication) {
        // The title is a button inside the logging screen's navigation bar (the Workout tab's bar sits behind the cover).
        let title = app.navigationBars.matching(NSPredicate(format: "identifier != 'Workout'")).buttons.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "title menu button missing")
        title.tap()
    }

    /// A title-menu item. The system drops the items' accessibility identifiers, so match the label.
    @MainActor
    private func menuItem(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    func testRenameFromTitleMenu() throws {
        let app = launchCover()
        openTitleMenu(app)
        let rename = menuItem(app, "Rename…")
        XCTAssertTrue(rename.waitForExistence(timeout: 5), "Rename item missing")
        rename.tap()

        let field = app.alerts["Rename Workout"].textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "rename alert missing")
        field.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) {
            app.menuItems["Select All"].tap()
        }
        field.typeText("Leg Day")
        app.alerts["Rename Workout"].buttons["Save"].firstMatch.tap()

        XCTAssertTrue(
            app.navigationBars.buttons["Leg Day"].firstMatch.waitForExistence(timeout: 5),
            "title did not change"
        )
    }

    @MainActor
    func testDiscardFromTitleMenu() throws {
        let app = launchCover()
        let any = app.descendants(matching: .any)
        openTitleMenu(app)
        let discard = menuItem(app, "Discard Workout")
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "Discard item missing")
        discard.tap()

        XCTAssertTrue(app.staticTexts["Discard workout?"].firstMatch.waitForExistence(timeout: 5))
        let confirm = app.buttons["discard.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(any["screen.workout"].waitForExistence(timeout: 10))
        XCTAssertTrue(any["screen.activeWorkout"].waitForNonExistence(timeout: 10))
    }
}
