import XCTest

/// Helpers shared by the Apple Fitness enrichment suites (`HealthEnrichment*UITests`), split into separate classes so the
/// sharded `./dev ui-test` can balance them. Prefixed `health` so they cannot clash with a suite's own private helpers.
extension XCTestCase {
    /// Launches with a running (minimised) sample workout and the full Health fixture.
    @MainActor
    func healthLaunchWithRunningWorkout() -> XCUIApplication {
        let app = XCUIApplication.launchedForTesting(["-healthFixture", "full", "-startSampleWorkout"])
        return app
    }

    /// The Settings sheet from the Workout tab's gear; `body` runs while it is up, then Done closes it.
    @MainActor
    func healthInSettings(_ app: XCUIApplication, _ body: () -> Void) {
        let gear = app.anyControl("toolbar.settings")
        XCTAssertTrue(gear.waitForExistence(timeout: 15), "no settings button")
        gear.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 10))
        body()
        let done = app.anyControl("settings.done")
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForNonExistence(timeout: 10))
    }

    /// The Apple Fitness toggle, scrolled into view.
    @MainActor
    func healthFitnessToggle(_ app: XCUIApplication) -> XCUIElement {
        let toggle = app.switches["settings.health.enabled"]
        for _ in 0..<5 where !toggle.exists || !toggle.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no Apple Fitness toggle")
        return toggle
    }

    /// Taps the switch itself (near the right end of the row), not the label beside it.
    @MainActor
    func healthFlip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5)).tap()
    }

    /// The switch settles on `value` ("1" on, "0" off) within a few seconds.
    @MainActor
    func healthExpectValue(_ toggle: XCUIElement, _ value: String, line: UInt = #line) {
        waitUntil(timeout: 4) { toggle.value as? String == value }
        XCTAssertEqual(toggle.value as? String, value, "\(toggle.debugDescription)", line: line)
    }

    /// Reopens the running workout, checks one set and finishes it, then dismisses the summary.
    @MainActor
    func healthFinishWorkout(_ app: XCUIApplication) {
        let any = app.descendants(matching: .any)
        let ring = app.buttons["resume.ring"].firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 10), "no resume ring")
        ring.tap()
        XCTAssertTrue(any["screen.activeWorkout"].waitForExistence(timeout: 15))

        // Check one set, then finish: the unchecked sets have no values, so the lighter dialog asks to finish.
        let check = app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.check'")
        ).element(boundBy: 0)
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        check.tap()
        let finish = app.anyControl("cover.finish")
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        finish.tap()
        let confirm = app.buttons["finish.finish"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "finish confirmation missing")
        confirm.tap()

        XCTAssertTrue(any["screen.finishSummary"].waitForExistence(timeout: 10), "finish summary missing")
        let done = app.buttons["summary.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(any["screen.finishSummary"].waitForNonExistence(timeout: 10))
        // The workout came from a template and ended differently, so "Update Template?" follows the summary.
        let keepTemplate = app.buttons["updateTemplate.keep"].firstMatch
        if keepTemplate.waitForExistence(timeout: 3) { keepTemplate.tap() }
    }

    /// A History row matching `format`, scrolling past the dashboard cards (the list is lazy, so rows below do not exist yet).
    @MainActor
    func healthHistoryRow(_ app: XCUIApplication, _ format: String, timeout: TimeInterval = 10) -> XCUIElement {
        let row = app.descendants(matching: .any).matching(NSPredicate(format: format)).firstMatch
        if row.waitForExistence(timeout: timeout) { return row }
        for _ in 0..<8 where !row.exists { app.swipeUp() }
        return row
    }

    @MainActor
    func healthFitnessRow(_ app: XCUIApplication, timeout: TimeInterval = 10) -> XCUIElement {
        healthHistoryRow(
            app,
            "identifier BEGINSWITH 'history.row.' AND label CONTAINS 'active calories'",
            timeout: timeout
        )
    }

    @MainActor
    func healthAnyRow(_ app: XCUIApplication) -> XCUIElement {
        healthHistoryRow(app, "identifier BEGINSWITH 'history.row.'")
    }
}
