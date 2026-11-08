import XCTest

/// The exercise detail (task 4.2): opened from the Exercises list, About and Records segments.
final class ExerciseDetailUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOpenSwitchToRecords() throws {
        let app = XCUIApplication.launchedPreview("Exercises")

        let any = app.descendants(matching: .any)
        try openBenchPress(app)

        XCTAssertTrue(any["screen.exerciseDetail"].waitForExistence(timeout: 5), "the detail did not open")
        let name = any["exerciseDetail.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.label, "Barbell Bench Press")

        let segment = app.segmentedControls["exerciseDetail.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 5))
        // Library exercises have no Edit item (the segmented control proves the detail's toolbar and content are laid out).
        any["exerciseDetail.edit"].assertStaysAbsent(for: 1, "a library exercise offers Edit")
        XCTAssertTrue(segment.buttons["About"].exists)
        // The sticky note is About content, below the segmented control (not between the name and it).
        let sticky = any["exerciseDetail.stickyNote"]
        XCTAssertTrue(sticky.waitForExistence(timeout: 5), "no sticky note in About")
        XCTAssertGreaterThan(sticky.frame.minY, segment.frame.maxY, "the sticky note is above the segmented control")
        segment.buttons["Records"].tap()

        // The sample history has Barbell Bench Press sessions, so at least the e1RM record exists.
        let e1rm = any["exerciseDetail.records.e1rm"]
        XCTAssertTrue(e1rm.waitForExistence(timeout: 5), "no Estimated 1RM record row")
        XCTAssertTrue(e1rm.label.hasPrefix("Estimated 1RM"), "label was \(e1rm.label)")
        XCTAssertTrue(any["exerciseDetail.records.heaviest"].exists)
        XCTAssertTrue(any["exerciseDetail.records.repsAtWeight.0"].exists)

        // History (task 4.3): at least one session, newest first.
        segment.buttons["History"].tap()
        let sessionCards = any.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'exerciseDetail.history.session.' AND NOT identifier CONTAINS '.set.'"
            )
        )
        XCTAssertTrue(sessionCards.firstMatch.waitForExistence(timeout: 5), "no History session")

        // Charts: the chart shows, and switching the metric keeps it.
        segment.buttons["Charts"].tap()
        XCTAssertTrue(any["exerciseDetail.chart.metric"].waitForExistence(timeout: 5))
        XCTAssertTrue(any["exerciseDetail.chart"].waitForExistence(timeout: 5), "no chart")
        let totalReps = app.buttons["exerciseDetail.chart.metric.totalReps"]
        XCTAssertTrue(totalReps.waitForExistence(timeout: 5))
        totalReps.tap()
        XCTAssertTrue(any["exerciseDetail.chart"].waitForExistence(timeout: 5), "chart gone after switching metric")
        app.buttons["exerciseDetail.chart.metric.volume"].tap()
        XCTAssertTrue(any["exerciseDetail.chart"].waitForExistence(timeout: 5), "chart gone after switching metric")

        segment.buttons["About"].tap()
        XCTAssertTrue(any["exerciseDetail.about.instructions"].waitForExistence(timeout: 5))
    }

    /// Re-pushing a detail fires a stray onDisappear that cancels its tasks: History must still load, not stay a placeholder.
    @MainActor
    func testReopenedDetailLoadsHistory() throws {
        let app = XCUIApplication.launchedPreview("Exercises")
        let any = app.descendants(matching: .any)

        try openBenchPress(app)
        XCTAssertTrue(any["screen.exerciseDetail"].waitForExistence(timeout: 5), "the detail did not open")
        let back = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "no back button")
        back.tap()
        XCTAssertTrue(any["screen.exercises"].waitForExistence(timeout: 10), "did not return to the list")

        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'exercises.row.' AND label BEGINSWITH 'Barbell Bench Press'")
        ).firstMatch
        if row.waitForExistence(timeout: 5) {
            row.tap()
        } else {
            try openBenchPress(app)
        }

        let segment = app.segmentedControls["exerciseDetail.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 5), "the detail did not reopen")
        segment.buttons["History"].tap()
        XCTAssertTrue(any["exerciseDetail.loading"].waitUntilGone(timeout: 10), "History stayed on its placeholder")
        let sessionCards = any.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'exerciseDetail.history.session.' AND NOT identifier CONTAINS '.set.'"
            )
        )
        XCTAssertTrue(sessionCards.firstMatch.waitForExistence(timeout: 5), "no History session after reopening")
    }

    /// From the Exercises list: searches for Barbell Bench Press (the sample history has sessions of it) and opens it.
    @MainActor
    private func openBenchPress(_ app: XCUIApplication) throws {
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.exercises"].waitForExistence(timeout: 10))
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'exercises.row.'")
        )
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 10), "no exercise rows")

        // On the closed Duo the system folds search into a button in the trailing strip; tap it to get the field.
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3), !app.buttons["Search"].firstMatch.exists {
            // Inside the tab shell the field sits above the first row until the list is pulled down.
            app.collectionViews.firstMatch.swipeDown()
        }
        if !search.waitForExistence(timeout: 3) {
            let button = app.buttons["Search"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            search.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "search field did not take focus")
        }
        search.typeText("Barbell Bench Press\n")

        let row = rows.matching(NSPredicate(format: "label BEGINSWITH 'Barbell Bench Press'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no Barbell Bench Press row")
        row.tap()
    }

    /// R4-06: the History segment's session header opens the workout in the History tab. Needs the whole tab shell
    /// (`-preview Root`), because the link is `AppNavigation.openWorkout`.
    @MainActor
    func testSessionOpensWorkout() throws {
        let app = XCUIApplication.launchedPreview("Root")

        let any = app.descendants(matching: .any)
        let tab = any["tab.exercises"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "no Exercises tab")
        tab.tap()
        try openBenchPress(app)

        let segment = app.segmentedControls["exerciseDetail.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 5))
        segment.buttons["History"].tap()
        let session = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'exerciseDetail.history.session.' AND identifier ENDSWITH '.open'"
            )
        ).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5), "no History session header")
        session.tap()
        XCTAssertTrue(any["history.detail"].waitForExistence(timeout: 5), "the session did not open its workout")
    }
}
