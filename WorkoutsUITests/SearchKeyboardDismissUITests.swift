import XCTest

/// While a search field has the keyboard, a tap on the screen's content puts the keyboard away, typed text or not; search
/// stays active. A result under the tap still opens on that same tap. Runs in the real tab shell (the `-preview` gallery places
/// search differently).
final class SearchKeyboardDismissUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHistoryTapPutsTheKeyboardAway() throws {
        let app = XCUIApplication.launchedForTesting(["-sampleWorkouts", "40"])
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(app.descendants(matching: .any)["screen.history"].waitForExistence(timeout: 10))
        app.assertTapOnHistoryContentPutsKeyboardAway()
    }

    /// With a query typed, the tap that puts the keyboard away still opens the result under it.
    @MainActor
    func testHistoryRowStillOpensWithTheKeyboardUp() throws {
        let app = XCUIApplication.launchedForTesting(["-sampleWorkouts", "40"])
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(app.descendants(matching: .any)["screen.history"].waitForExistence(timeout: 10))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6), "no search field")
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 6), "no keyboard after tapping search")
        // A query hides the dashboard, so the first result sits above the keyboard.
        field.typeText("Pull")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6), "no result row")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "keyboard gone before the tap")
        row.tap()
        XCTAssertTrue(
            app.buttons["workoutDetail.edit"].waitForExistence(timeout: 8),
            "a result did not open on the first tap with the keyboard up"
        )
    }

    /// With a query typed, a tap on content still puts the keyboard away; the query and the search stay.
    @MainActor
    func testHistoryTapWithAQueryPutsTheKeyboardAway() throws {
        let app = XCUIApplication.launchedForTesting(["-sampleWorkouts", "40"])
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(app.descendants(matching: .any)["screen.history"].waitForExistence(timeout: 10))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6), "no search field")
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 6), "no keyboard after tapping search")
        field.typeText("Pull")
        let header = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' 2026'")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 6), "no month header to tap")
        app.tapAndAssertKeyboardStaysAway(at: header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "Pull", "the query was lost")
        XCTAssertTrue(app.descendants(matching: .any)["screen.history"].exists, "History is not showing")
        XCTAssertFalse(app.buttons["workoutDetail.edit"].exists, "a detail was pushed")
    }

    @MainActor
    func testExercisesTapPutsTheKeyboardAwayAndClearKeepsIt() throws {
        let app = XCUIApplication.launchedForTesting(["-sampleWorkouts", "40"])
        app.selectTab("tab.exercises", label: "Exercises")
        XCTAssertTrue(app.descendants(matching: .any)["screen.exercises"].waitForExistence(timeout: 10))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6), "no search field")
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 6), "no keyboard after tapping search")
        field.typeText("bench")

        let clear = app.buttons.matching(NSPredicate(format: "label ==[c] 'Clear text'")).firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 4), "no Clear text button")
        clear.tap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "keyboard went away after Clear text")

        // The filter pills' row has blank space to the right of the pills: a spot with nothing under it.
        let pill = app.buttons["exercises.filter.category"]
        XCTAssertTrue(pill.exists, "no filter pill")
        let blank = pill.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: pill.frame.width + 40, dy: pill.frame.height / 2))
        app.tapAndAssertKeyboardStaysAway(at: blank)
    }
}

extension XCUIApplication {
    /// With the search keyboard up on History, taps the "Per week" label (plain text, above the keyboard), expects the
    /// keyboard gone within 6 s and not back for 4 s, with the search field still present.
    @MainActor
    func assertTapOnHistoryContentPutsKeyboardAway(file: StaticString = #filePath, line: UInt = #line) {
        let field = searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6), "no search field", file: file, line: line)
        field.tap()
        XCTAssertTrue(
            keyboards.firstMatch.waitForExistence(timeout: 6),
            "no keyboard after tapping search",
            file: file,
            line: line
        )
        let label = staticTexts["Per week"]
        XCTAssertTrue(label.waitForExistence(timeout: 6), "no plain text to tap", file: file, line: line)
        tapAndAssertKeyboardStaysAway(
            at: label.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
            file: file,
            line: line
        )
        XCTAssertTrue(searchFields.firstMatch.exists, "search closed with the keyboard", file: file, line: line)
    }

    @MainActor
    func tapAndAssertKeyboardStaysAway(
        at coordinate: XCUICoordinate,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        coordinate.tap()
        XCTAssertTrue(
            keyboards.firstMatch.waitUntilGone(timeout: 6),
            "tap did not put the keyboard away",
            file: file,
            line: line
        )
        keyboards.firstMatch.assertStaysAbsent(for: 4, "keyboard came back by itself", file: file, line: line)
    }
}
