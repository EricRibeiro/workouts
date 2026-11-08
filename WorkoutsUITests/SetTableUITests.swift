import XCTest

/// The set table on the gallery entry `SetTable` (task 2.3): an active workout from the first sample template. Check a set,
/// Add Set, and swipe-delete a row.
final class SetTableUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.launchedPreview("SetTable", waitingFor: "screen.setTable")
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
        let knownChecks = checks.allElementsBoundByIndex.map(\.identifier)
        addSet.tap()
        // The table is lazy: the new row can push the next block's first row out of the tree (a block note under the
        // first name does that), so look for the new row rather than for one more row.
        waitUntil(timeout: 5) {
            checks.allElementsBoundByIndex.contains(where: { !knownChecks.contains($0.identifier) })
        }

        // Checking the new, empty row is refused: nothing to record, so it stays "Not done".
        let newCheck = checks.allElementsBoundByIndex.first { !knownChecks.contains($0.identifier) }
        XCTAssertNotNil(newCheck, "could not find the new row")
        if let newCheck {
            XCTAssertEqual(newCheck.value as? String, "Not done")
            newCheck.tap()
            XCTAssertEqual(newCheck.value as? String, "Not done", "an empty set must not be checkable")
        }

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

    @MainActor
    private func waitForCount(_ query: XCUIElementQuery, _ count: Int) -> Bool {
        waitUntil(timeout: 5) { query.count == count }
    }
}
