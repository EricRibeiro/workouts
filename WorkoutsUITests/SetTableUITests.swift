import XCTest

/// The set table on the gallery entry `SetTable` (task 2.3): an active workout from the first sample template. Check a set,
/// Add Set, and swipe-delete a row.
final class SetTableUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-preview", "SetTable"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.setTable"].waitForExistence(timeout: 10))
        return app
    }

    private func checkButtons(_ app: XCUIApplication) -> XCUIElementQuery {
        app.switches.matching(NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.check'"))
    }

    @MainActor
    func testCheckAddAndDelete() throws {
        let app = launch()

        let checks = checkButtons(app)
        let first = checks.element(boundBy: 0)
        XCTAssertTrue(first.waitForExistence(timeout: 10), "no set rows")
        let initialCount = checks.count
        XCTAssertGreaterThanOrEqual(initialCount, 2)

        // Check the first set: it fills from Previous and the row reads checked.
        XCTAssertEqual(first.value as? String, "Not done")
        first.tap()
        XCTAssertEqual(first.value as? String, "Done")

        // Add Set appends a row to the first exercise.
        let addSet = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'settable.addset.'")
        )
        .element(boundBy: 0)
        XCTAssertTrue(addSet.exists)
        XCTAssertEqual(addSet.label, "Add set")
        addSet.tap()
        XCTAssertEqual(checks.count, initialCount + 1)

        // Swipe the last of the first exercise's rows to the left: Delete removes it.
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier MATCHES 'setrow\\\\.[0-9A-Fa-f-]{36}'")
        )
        let target = rows.element(boundBy: 1)
        XCTAssertTrue(target.exists)
        target.swipeLeft()
        let delete = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.delete'")
        )
        .firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "swipe did not reveal Delete")
        delete.tap()
        XCTAssertTrue(waitForCount(checks, initialCount), "row was not deleted")
        XCTAssertEqual(checks.count, initialCount)
    }

    private func waitForCount(_ query: XCUIElementQuery, _ count: Int) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if query.count == count { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }
}
