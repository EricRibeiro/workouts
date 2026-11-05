import XCTest

/// The History Calendar sheet on the gallery entry `History` (task 5.4): month grid with marked days, Previous / Next
/// month, and a marked day closing the sheet and pushing that workout.
final class HistoryCalendarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchAndOpenCalendar() -> XCUIApplication {
        let app = XCUIApplication.launchedPreview("History", waitingFor: "screen.history")
        let any = app.descendants(matching: .any)
        let open = app.buttons["history.calendar"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), "no Calendar toolbar item")
        open.tap()
        XCTAssertTrue(any["screen.calendar"].waitForExistence(timeout: 5), "the calendar sheet did not open")
        return app
    }

    /// Day buttons whose label says they have workouts ("Tuesday, November 3, 1 workout").
    private func markedDays(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'calendar.day.' AND label MATCHES '.*[0-9]+ workouts?'")
        )
    }

    @MainActor
    func testMarkedDayClosesSheetAndPushesWorkout() throws {
        let app = launchAndOpenCalendar()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(app.buttons["calendar.prev"].exists)
        XCTAssertTrue(app.buttons["calendar.next"].exists)
        XCTAssertTrue(app.buttons["calendar.done"].exists)

        // The sample data spans weeks: the current month or the previous one has a marked day.
        if markedDays(app).count == 0 {
            app.buttons["calendar.prev"].tap()
        }
        let marked = markedDays(app).element(boundBy: 0)
        XCTAssertTrue(marked.waitForExistence(timeout: 5), "no marked day this or last month")
        XCTAssertTrue(marked.label.contains("workout"), marked.label)

        marked.tap()
        // A day with several workouts lists them first; open the first.
        let firstOfDay = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'calendar.workout.'")
        ).firstMatch
        if firstOfDay.waitForExistence(timeout: 2) { firstOfDay.tap() }

        XCTAssertTrue(any["history.detail"].waitForExistence(timeout: 8), "the workout did not open")
        XCTAssertFalse(any["screen.calendar"].exists, "the sheet is still up")
    }

    @MainActor
    func testPreviousAndNextChangeTheTitle() throws {
        let app = launchAndOpenCalendar()
        let title = app.staticTexts["calendar.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let current = title.label
        XCTAssertNotNil(current.range(of: #"^[A-Z][a-z]+ 20[0-9]{2}$"#, options: .regularExpression), current)

        app.buttons["calendar.prev"].tap()
        let previous = app.staticTexts["calendar.title"].label
        XCTAssertNotEqual(previous, current)

        app.buttons["calendar.next"].tap()
        XCTAssertEqual(app.staticTexts["calendar.title"].label, current)
        app.buttons["calendar.next"].tap()
        XCTAssertNotEqual(app.staticTexts["calendar.title"].label, current)
    }

    @MainActor
    func testDoneDismisses() throws {
        let app = launchAndOpenCalendar()
        app.buttons["calendar.done"].tap()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 5))
        XCTAssertFalse(any["screen.calendar"].waitForExistence(timeout: 2))
    }
}
