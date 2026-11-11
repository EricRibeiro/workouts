import XCTest

/// The fitness-skin controls: a template card's play button, the Skip / +30 s pair beside the minimised ring while a rest runs,
/// and the inline rest row under a checked set.
final class FitnessSkinUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func playButtons(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start ' AND identifier ENDSWITH '.start'"))
    }

    private func firstCheck(_ app: XCUIApplication) -> XCUIElement {
        app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.check'")
        ).element(boundBy: 0)
    }

    @MainActor
    func testPlayButtonStartsTheWorkout() throws {
        let app = XCUIApplication.launchedForTesting(["-seedSampleData"])
        let play = playButtons(app).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 10), "no template card play button")
        play.tap()
        XCTAssertTrue(
            app.anyControl("cover.finish").waitForExistence(timeout: 10),
            "the play button did not open the logging screen"
        )
        XCTAssertTrue(app.descendants(matching: .any)["screen.activeWorkout"].exists)
    }

    @MainActor
    func testPlayButtonWithAWorkoutRunningAsksFirst() throws {
        let app = XCUIApplication.launchedForTesting(["-startSampleWorkout"])
        let any = app.descendants(matching: .any)
        // The sample workout runs minimised on the Workout tab.
        XCTAssertTrue(app.buttons["resume.ring"].firstMatch.waitForExistence(timeout: 15), "no minimised workout")
        let play = playButtons(app).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 10), "no template card play button")
        play.tap()

        XCTAssertTrue(app.staticTexts["Workout in progress"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(any["screen.activeWorkout"].exists, "the alert comes before any cover")
        let cancel = app.buttons["start.cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "alert has no Cancel button")
        cancel.tap()

        XCTAssertTrue(app.staticTexts["Workout in progress"].firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertFalse(any["screen.activeWorkout"].exists, "Cancel must not open or start a workout")
        XCTAssertTrue(app.buttons["resume.ring"].firstMatch.exists, "the running workout should still be the only one")
        XCTAssertEqual(
            app.buttons.matching(identifier: "resume.ring").count,
            1,
            "Cancel left more than one running workout"
        )
    }

    @MainActor
    func testMinimisedRestShowsSkipAndPlus30() throws {
        // The sample workout runs minimised with a 5-minute rest.
        let app = XCUIApplication.launchedForTesting(["-startSampleWorkout"])
        let ring = app.buttons["resume.ring"].firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 15), "no minimised workout")
        let skip = app.buttons["resume.rest.skip"].firstMatch
        let plus30 = app.buttons["resume.rest.plus30"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "Skip missing beside the ring while a rest runs")
        XCTAssertTrue(plus30.exists, "+30 s missing beside the ring while a rest runs")

        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5), "Skip stayed after the rest was skipped")
        XCTAssertTrue(plus30.waitForNonExistence(timeout: 5), "+30 s stayed after the rest was skipped")
        XCTAssertTrue(ring.exists, "the ring must stay while the workout runs")
    }

    @MainActor
    func testInlineRestRowSkipAndPlus30() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let check = firstCheck(app)
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        check.tap()

        let row = app.anyControl("rest.row")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "checking a set did not show the inline rest row")
        XCTAssertFalse(app.buttons["rest.toolbar.skip"].exists, "the toolbar must not duplicate Skip")
        XCTAssertFalse(app.buttons["rest.toolbar.plus30"].exists, "the toolbar must not duplicate +30 s")

        let countdown = app.anyControl("rest.row.countdown")
        XCTAssertTrue(countdown.waitForExistence(timeout: 5))
        func remaining() -> Int? { seconds(from: countdown.value as? String) }
        let before = try XCTUnwrap(remaining(), "countdown value \(String(describing: countdown.value))")

        let plus30 = app.buttons["rest.row.plus30"].firstMatch
        XCTAssertTrue(plus30.exists)
        plus30.tap()
        expectation(
            for: NSPredicate { _, _ in (remaining() ?? 0) >= before + 25 },
            evaluatedWith: nil
        )
        waitForExpectations(timeout: 5)

        let skip = app.buttons["rest.row.skip"].firstMatch
        XCTAssertTrue(skip.exists)
        skip.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "the inline rest row stayed after Skip")
    }
}
