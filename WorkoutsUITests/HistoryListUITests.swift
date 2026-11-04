import XCTest

/// The History list on the gallery entry `History` (task 5.1): month headers, rows, the push to the detail, Delete
/// behind a confirmation, and the PRs search scope.
final class HistoryListUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.row.'")
        )
    }

    /// The first row, scrolling past the dashboard cards (the list is lazy, so rows below them do not exist yet).
    @MainActor
    private func firstRow(_ app: XCUIApplication) -> XCUIElement {
        let first = rows(app).element(boundBy: 0)
        for _ in 0..<8 {
            if first.waitForExistence(timeout: 2) && first.isHittable { break }
            app.swipeUp()
        }
        return first
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-preview", "History"]
        app.launch()
        return app
    }

    @MainActor
    func testMonthHeaderRowsAndDetail() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 10))

        let rows = rows(app)
        XCTAssertTrue(firstRow(app).exists, "no history rows")

        let header = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES '[A-Z][a-z]+ 20[0-9]{2}'")
        ).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5), "no month header")

        // "name, date, duration, volume[, N PRs]" as one element.
        let first = rows.element(boundBy: 0)
        XCTAssertTrue(first.label.contains("min") || first.label.contains("<1min"), first.label)
        XCTAssertTrue(first.label.contains(" lb") || first.label.contains(" kg"), first.label)

        first.tap()
        XCTAssertTrue(any["history.detail"].waitForExistence(timeout: 5), "tapping a row did not open the detail")

        // The system back button; its automation type is unreliable on the Duo's strip, so fall back to the edge swipe.
        let back = app.buttons["BackButton"].firstMatch
        if back.waitForExistence(timeout: 2) {
            back.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        }
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 5), "back did not return to the list")
        XCTAssertFalse(any["history.detail"].exists)
    }

    @MainActor
    func testDashboardCardsAndLastWorkoutPush() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        for id in ["history.card.thisWeek", "history.card.recentPRs", "history.card.lastWorkout"] {
            let card = any[id]
            for _ in 0..<6 where !(card.exists && card.isHittable) { app.swipeUp() }
            XCTAssertTrue(card.waitForExistence(timeout: 5), "no card \(id)")
            XCTAssertFalse(card.label.isEmpty, "card \(id) has no sentence")
        }
        let last = any["history.card.lastWorkout"]
        XCTAssertTrue(last.label.hasPrefix("Last workout, "), last.label)
        XCTAssertTrue(any["history.card.recentPRs"].label.hasPrefix("Recent PRs, "))
        last.tap()
        XCTAssertTrue(any["history.detail"].waitForExistence(timeout: 5), "the Last Workout card did not push")
    }

    @MainActor
    func testSwipeDeleteAsksFirstThenRemovesTheRow() throws {
        let app = launch()
        let rows = rows(app)
        let first = firstRow(app)
        XCTAssertTrue(first.exists, "no history rows")
        let id = first.identifier
        let label = first.label

        first.swipeLeft()
        let delete = app.buttons["history.delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "no Delete swipe action")
        delete.tap()

        let confirm = app.buttons["Delete Workout"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no confirmation")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: id).firstMatch.exists,
            "the row left before the confirmation (\(label))"
        )
        confirm.tap()

        let gone = NSPredicate(format: "exists == false")
        let removed = XCTNSPredicateExpectation(
            predicate: gone,
            object: app.descendants(matching: .any).matching(identifier: id).firstMatch
        )
        XCTAssertEqual(XCTWaiter().wait(for: [removed], timeout: 5), .completed, "row \(label) is still there")
    }

    @MainActor
    func testPRsScopeNarrowsTheList() throws {
        let app = launch()
        let rows = rows(app)
        XCTAssertTrue(
            app.descendants(matching: .any)["screen.history"].waitForExistence(timeout: 10),
            "no history screen"
        )

        // On the closed Duo the system folds search into a button in the trailing strip; tap it to get the field.
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3) {
            let button = app.buttons["Search"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()

        let prs = app.buttons["PRs"].firstMatch
        XCTAssertTrue(prs.waitForExistence(timeout: 5), "no PRs scope\n\(app.debugDescription)")
        prs.tap()

        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 5), "no rows in the PRs scope")
        let narrowed = (0..<min(rows.count, 8)).map { rows.element(boundBy: $0).label }
        XCTAssertFalse(narrowed.isEmpty)
        // Every sample workout sets records (steady progression), so the scope keeps all of them; the narrowing
        // itself is covered by the kit's HistoryList filter tests. (Row counts are not compared: the list is lazy and
        // the weekly chart above All changes how many rows are loaded.)
        for label in narrowed {
            XCTAssertTrue(label.contains(" PR"), "row without PRs in the PRs scope: \(label)")
        }
    }
}
