import XCTest

extension XCUIApplication {
    /// Every template card on the Workout tab.
    var templateCards: XCUIElementQuery {
        buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workout.template.'"))
    }

    var firstTemplateCard: XCUIElement { templateCards.firstMatch }

    /// Selects a tab by identifier or label. The closed Duo's trailing strip drops the tab identifiers; the buttons keep
    /// their labels.
    @MainActor
    func selectTab(_ id: String, label: String, timeout: TimeInterval = 10) {
        let tab = buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", id, label)).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: timeout), "\(id) missing")
        tab.tap()
    }

    /// Opens the screen's search field, taps the control that closes it (the "x", or Cancel) and asserts search stays closed.
    @MainActor
    func assertSearchClosesAndStaysClosed(file: StaticString = #filePath, line: UInt = #line) {
        let field = searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6), "no search field", file: file, line: line)
        field.tap()
        XCTAssertTrue(
            keyboards.firstMatch.waitForExistence(timeout: 6),
            "no keyboard after tapping search",
            file: file,
            line: line
        )

        let close = buttons.matching(NSPredicate(format: "label ==[c] 'close' OR label ==[c] 'cancel'")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 4), "no close control for search", file: file, line: line)
        close.tap()

        XCTAssertTrue(keyboards.firstMatch.waitUntilGone(timeout: 6), "search did not close", file: file, line: line)
        keyboards.firstMatch.assertStaysAbsent(
            for: 4,
            "search reopened by itself after closing",
            file: file,
            line: line
        )
    }
}
