import XCTest

/// The opt-in Fitness enrichment wired into the app (PLAN 7.1b e3b): off by default; the Settings toggle turns it on, a
/// finished workout then picks up the canned Fitness workout from `-healthFixture full` (its History row then shows the
/// active calories: the row's label says "N active calories", the text on screen "N kcal"); turning it off can remove what
/// was added. Nothing here touches the real
/// Health store: plain `-uiTesting` has no source at all.
final class HealthEnrichmentUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches with a running (minimised) sample workout and the full Health fixture.
    @MainActor
    private func launchWithRunningWorkout() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-healthFixture", "full", "-startSampleWorkout"]
        app.launch()
        return app
    }

    /// The closed Duo's trailing strip drops the tab identifiers; the buttons keep their labels.
    @MainActor
    private func selectTab(_ app: XCUIApplication, _ id: String, label: String) {
        let tab = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", id, label)).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "\(id) missing")
        tab.tap()
    }

    /// The Settings sheet from the Workout tab's gear; `body` runs while it is up, then Done closes it.
    @MainActor
    private func inSettings(_ app: XCUIApplication, _ body: () -> Void) {
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
    private func fitnessToggle(_ app: XCUIApplication) -> XCUIElement {
        let toggle = app.switches["settings.health.enabled"]
        for _ in 0..<5 where !toggle.exists || !toggle.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no Apple Fitness toggle")
        return toggle
    }

    /// Taps the switch itself (near the right end of the row), not the label beside it.
    @MainActor
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5)).tap()
    }

    /// The switch settles on `value` ("1" on, "0" off) within a few seconds.
    @MainActor
    private func expectValue(_ toggle: XCUIElement, _ value: String, line: UInt = #line) {
        let deadline = Date.now.addingTimeInterval(4)
        while Date.now < deadline, toggle.value as? String != value { usleep(200_000) }
        XCTAssertEqual(toggle.value as? String, value, "\(toggle.debugDescription)", line: line)
    }

    /// Reopens the running workout, checks one set and finishes it, then dismisses the summary.
    @MainActor
    private func finishWorkout(_ app: XCUIApplication) {
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
    private func historyRow(_ app: XCUIApplication, _ format: String, timeout: TimeInterval = 10) -> XCUIElement {
        let row = app.descendants(matching: .any).matching(NSPredicate(format: format)).firstMatch
        if row.waitForExistence(timeout: timeout) { return row }
        for _ in 0..<8 where !row.exists { app.swipeUp() }
        return row
    }

    @MainActor
    private func fitnessRow(_ app: XCUIApplication, timeout: TimeInterval = 10) -> XCUIElement {
        historyRow(app, "identifier BEGINSWITH 'history.row.' AND label CONTAINS 'active calories'", timeout: timeout)
    }

    @MainActor
    private func anyRow(_ app: XCUIApplication) -> XCUIElement {
        historyRow(app, "identifier BEGINSWITH 'history.row.'")
    }

    @MainActor
    func testOffByDefaultNothingIsAdded() throws {
        let app = launchWithRunningWorkout()
        inSettings(app) {
            XCTAssertEqual(fitnessToggle(app).value as? String, "0")
        }
        finishWorkout(app)
        selectTab(app, "tab.history", label: "History")
        XCTAssertTrue(anyRow(app).exists, "the finished workout is missing from History")
        // Give a (wrongly) triggered lookup time to land before asserting its absence.
        sleep(3)
        XCTAssertFalse(fitnessRow(app, timeout: 3).exists, "Fitness data was added while the setting is off")
    }

    @MainActor
    func testTurningOnThenFinishingAddsFitnessAndRemoveClearsIt() throws {
        let app = launchWithRunningWorkout()
        inSettings(app) {
            let toggle = fitnessToggle(app)
            flip(toggle)
            expectValue(toggle, "1")
        }
        finishWorkout(app)
        selectTab(app, "tab.history", label: "History")
        XCTAssertTrue(fitnessRow(app).exists, "the finished workout never got its Fitness data")

        // Off, then Cancel: stays on and keeps the data.
        selectTab(app, "tab.workout", label: "Workout")
        inSettings(app) {
            let toggle = fitnessToggle(app)
            flip(toggle)
            XCTAssertTrue(app.alerts["Turn Off Apple Fitness?"].waitForExistence(timeout: 5))
            app.alerts.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(app.alerts["Turn Off Apple Fitness?"].waitForNonExistence(timeout: 5))
            expectValue(toggle, "1")
        }

        // Off, then Remove: the data goes.
        inSettings(app) {
            let toggle = fitnessToggle(app)
            flip(toggle)
            XCTAssertTrue(app.alerts["Turn Off Apple Fitness?"].waitForExistence(timeout: 5))
            app.alerts.buttons["settings.health.remove"].firstMatch.tap()
            XCTAssertTrue(app.alerts["Turn Off Apple Fitness?"].waitForNonExistence(timeout: 5))
            expectValue(toggle, "0")
        }
        selectTab(app, "tab.history", label: "History")
        XCTAssertTrue(anyRow(app).exists)
        XCTAssertFalse(fitnessRow(app, timeout: 3).exists, "Remove Fitness Data left the data in place")
    }

    @MainActor
    func testTurningOffAndKeepingLeavesTheData() throws {
        let app = launchWithRunningWorkout()
        inSettings(app) { flip(fitnessToggle(app)) }
        finishWorkout(app)
        selectTab(app, "tab.history", label: "History")
        XCTAssertTrue(fitnessRow(app).exists)

        selectTab(app, "tab.workout", label: "Workout")
        inSettings(app) {
            let toggle = fitnessToggle(app)
            flip(toggle)
            XCTAssertTrue(app.alerts["Turn Off Apple Fitness?"].waitForExistence(timeout: 5))
            app.alerts.buttons["settings.health.keep"].firstMatch.tap()
            expectValue(toggle, "0")
        }
        selectTab(app, "tab.history", label: "History")
        XCTAssertTrue(fitnessRow(app).exists, "Keep Fitness Data dropped the data")
    }

    @MainActor
    func testSettingsSectionOnlyWhereHealthIsAvailable() throws {
        let without = XCUIApplication()
        without.launchArguments += ["-uiTesting", "-preview", "Settings"]
        without.launch()
        XCTAssertTrue(without.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(without.anyControl("settings.weeklyGoal").waitForExistence(timeout: 5))
        for _ in 0..<3 { without.swipeUp() }
        XCTAssertFalse(without.anyControl("settings.health.enabled").exists)
    }
}
