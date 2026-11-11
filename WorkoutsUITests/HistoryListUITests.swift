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
    private func firstRow(_ app: XCUIApplication, timeout: TimeInterval = 2) -> XCUIElement {
        let first = rows(app).element(boundBy: 0)
        for _ in 0..<8 {
            if first.waitForExistence(timeout: timeout) && first.isHittable { break }
            app.swipeUp()
        }
        return first
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.launchedPreview("History")
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
        XCTAssertTrue(any["history.detail"].waitUntilGone(timeout: 5), "the detail is still up after back")
    }

    /// The detail's title and toolbar belong to the first frame of the push (backlog: "History detail jumps after the
    /// push"): they must not wait for the detail's off-main derivation to land. `-slowLoads` holds that derivation for 3 s
    /// (the History summary too, so the rows arrive late), which makes the check deterministic rather than a race.
    @MainActor
    func testDetailHasTitleAndToolbarFromTheFirstFrame() throws {
        let app = XCUIApplication.launchedPreview(
            "History",
            extraArguments: ["-slowLoads", "3000"],
            waitingFor: "screen.history"
        )
        let any = app.descendants(matching: .any)

        // The rows come from the held summary: wait it out (the first wait covers the 3 s), scrolling past the dashboard.
        let first = firstRow(app, timeout: 6)
        XCTAssertTrue(first.exists, "no history rows")
        // The row's label is "name, date, duration, volume[, N PRs]".
        let name = try XCTUnwrap(first.label.components(separatedBy: ",").first)
        first.tap()

        // The pushed screen itself: the bar's title and its buttons, asserted without waiting, before the content exists.
        app.assertChromeImmediately(title: name, buttons: ["workoutDetail.edit", "workoutDetail.delete"])
        XCTAssertFalse(any["history.detail"].exists, "the detail's content was there before its load finished")
    }

    @MainActor
    func testRowEditAndSaveAsTemplate() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 10))

        // Edit from the context menu opens the past-workout editor; Cancel returns to the list.
        let first = firstRow(app)
        XCTAssertTrue(first.exists, "no history rows")
        first.press(forDuration: 1.0)
        let edit = app.buttons["history.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "no Edit in the context menu")
        edit.tap()
        XCTAssertTrue(any["screen.pastEditor"].waitForExistence(timeout: 5), "Edit did not open the editor")
        app.buttons["pastEditor.cancel"].tap()
        XCTAssertTrue(firstRow(app).waitForExistence(timeout: 5), "Cancel did not return to the list")
        XCTAssertTrue(any["screen.pastEditor"].waitUntilGone(timeout: 5), "the editor is still up after Cancel")

        // Save as Template presents the sheet; Cancel dismisses it.
        firstRow(app).press(forDuration: 1.0)
        let save = app.buttons["history.saveTemplate"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "no Save as Template in the context menu")
        save.tap()
        XCTAssertTrue(
            any["workoutDetail.saveTemplate.sheet"].waitForExistence(timeout: 5),
            "Save as Template did not open the sheet"
        )
        app.buttons["workoutDetail.saveTemplate.cancel"].tap()
        XCTAssertTrue(firstRow(app).waitForExistence(timeout: 5), "Cancel did not return to the list")
        XCTAssertTrue(
            any["workoutDetail.saveTemplate.sheet"].waitUntilGone(timeout: 5),
            "the sheet is still up after Cancel"
        )
    }

    @MainActor
    func testDashboardCardsAndLastWorkoutPush() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        // The summary is computed off the main thread (6.4), so the cards land a moment after launch: wait for the
        // first one before scrolling, or the swipes run past where they appear.
        XCTAssertTrue(any["history.card.thisWeek"].waitForExistence(timeout: 10), "the dashboard never appeared")
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

        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: id).firstMatch.waitUntilGone(timeout: 5),
            "row \(label) is still there"
        )
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

        // Cancelling the search must also drop the scope: the scope bar is gone with the search, so a PRs scope left
        // behind would filter the list (and hide the dashboard) with nothing on screen saying so.
        // (The search field's dismiss button is labelled "close" on this OS; older ones say "Cancel".)
        let cancel = app.buttons.matching(NSPredicate(format: "label IN {'close', 'Cancel'}")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "no Cancel button\n\(app.debugDescription)")
        cancel.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["history.weeklyChart"].waitForExistence(timeout: 5),
            "the dashboard did not come back after cancelling a PRs search\n\(app.debugDescription)"
        )
    }

    /// A failed summary read must say so, with Retry (review H3-4), instead of a dashboard over no rows. `-failHistoryLoads`
    /// fails the first read only; Retry runs the load again and the rows arrive.
    @MainActor
    func testFailedLoadShowsRetryAndRecovers() throws {
        let app = XCUIApplication.launchedPreview(
            "History",
            extraArguments: ["-failHistoryLoads", "1"],
            waitingFor: "screen.history"
        )
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["history.loadFailed"].waitForExistence(timeout: 10), "no load error\n\(app.debugDescription)")
        XCTAssertFalse(rows(app).element(boundBy: 0).exists, "rows shown beside the load error")

        let retry = app.buttons["Retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5), "no Retry button\n\(app.debugDescription)")
        retry.tap()

        XCTAssertTrue(firstRow(app, timeout: 5).exists, "Retry did not bring the rows back")
        XCTAssertTrue(any["history.loadFailed"].waitUntilGone(timeout: 5), "the error stayed after a good load")
    }

    /// The weekly chart's mode picker swaps the chart and its spoken summary between Workouts and Volume.
    @MainActor
    func testWeeklyChartModeSwitchesBetweenWorkoutsAndVolume() throws {
        let app = launch()
        let chart = app.descendants(matching: .any)["history.weeklyChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 10), "no weekly chart")
        XCTAssertTrue(chart.label.hasPrefix("Workouts per week"), chart.label)

        let picker = app.descendants(matching: .any)["history.weeklyChart.mode"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "no chart mode picker")
        picker.buttons["Volume"].tap()
        expectation(
            for: NSPredicate(format: "label BEGINSWITH 'Volume per week'"),
            evaluatedWith: chart
        )
        waitForExpectations(timeout: 5)

        picker.buttons["Workouts"].tap()
        expectation(
            for: NSPredicate(format: "label BEGINSWITH 'Workouts per week'"),
            evaluatedWith: chart
        )
        waitForExpectations(timeout: 5)
    }
}
