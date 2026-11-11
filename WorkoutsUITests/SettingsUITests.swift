import XCTest

/// The Settings form on the gallery entry `Settings` (task 5.7a): the controls respond and carry their ids.
final class SettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        // Launch-argument defaults override the stored values, so a run never depends on an earlier one.
        XCUIApplication.launchedForTesting(
            [
                "-preview", "Settings",
                "-defaultUnit", "lb", "-defaultRestSeconds", "90", "-weeklyGoal", "3", "-e1rmFormula", "epley",
            ] + extra
        )
    }

    @MainActor
    func testUnitSegmentedControlSwitchesToKg() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.settings"].waitForExistence(timeout: 10))

        let unit = app.segmentedControls["settings.defaultUnit"]
        XCTAssertTrue(unit.waitForExistence(timeout: 5), "no unit control")
        XCTAssertTrue(unit.buttons["lb"].isSelected)
        unit.buttons["kg"].tap()
        XCTAssertTrue(unit.buttons["kg"].isSelected)
        XCTAssertFalse(unit.buttons["lb"].isSelected)

        let formula = app.segmentedControls["settings.e1rmFormula"]
        XCTAssertTrue(formula.exists)
        formula.buttons["Brzycki"].tap()
        XCTAssertTrue(formula.buttons["Brzycki"].isSelected)
    }

    @MainActor
    func testFullExerciseNamesToggleIsOffByDefault() throws {
        let app = launch()
        let toggle = app.switches["settings.fullExerciseNames"]
        for _ in 0..<4 where !toggle.exists { app.swipeUp() }
        XCTAssertTrue(toggle.exists, "no full exercise names toggle")
        XCTAssertEqual(toggle.value as? String, "0")
    }

    @MainActor
    func testWeeklyGoalStepperIncrements() throws {
        let app = launch()
        let stepper = app.steppers["settings.weeklyGoal"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 10), "no weekly goal stepper")
        XCTAssertEqual(stepper.value as? String, "3 workouts per week")
        stepper.buttons.element(boundBy: 1).tap()
        XCTAssertEqual(stepper.value as? String, "4 workouts per week")
    }

    @MainActor
    func testRestPickerShowsOneThirtyAndRowsExist() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        let rest = any["settings.defaultRestSeconds"]
        XCTAssertTrue(rest.waitForExistence(timeout: 10), "no rest picker")
        let value = (rest.value as? String) ?? ""
        XCTAssertTrue(rest.label.contains("1:30") || value.contains("1:30"), "label \(rest.label), value \(value)")

        XCTAssertTrue(any["settings.keepScreenOn"].exists, "keepScreenOn")
        // The Media rows sit below the Display section, past the fold on the closed display; the list only builds rows
        // near the viewport.
        let videos = any["settings.downloadAllVideos"]
        for _ in 0..<4 where !videos.exists { app.swipeUp() }
        XCTAssertTrue(videos.exists, "downloadAllVideos")
        // The iCloud row sits below the fold on the closed display; the list only builds rows near the viewport.
        let icloud = any["settings.iCloudStatus"]
        for _ in 0..<4 where !icloud.exists { app.swipeUp() }
        XCTAssertTrue(icloud.exists, "iCloudStatus")
    }

    // MARK: Turning off video downloads

    /// Launches with "Download all videos" on and the media cache empty or holding one dummy video; returns the toggle.
    @MainActor
    private func launchWithVideoDownloads(cache: String) -> (app: XCUIApplication, toggle: XCUIElement) {
        let app = launch(["-downloadAllVideos", "YES", "-videoCache", cache])
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 10))
        let toggle = app.switches["settings.downloadAllVideos"]
        for _ in 0..<5 where !toggle.exists || !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no Download all videos toggle")
        XCTAssertEqual(toggle.value as? String, "1")
        return (app, toggle)
    }

    /// Taps the switch itself (near the right end of the row), not the label beside it.
    @MainActor
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5)).tap()
    }

    @MainActor
    private func expectValue(_ toggle: XCUIElement, _ value: String, line: UInt = #line) {
        waitUntil(timeout: 5) { toggle.value as? String == value }
        XCTAssertEqual(toggle.value as? String, value, line: line)
    }

    @MainActor
    func testTurningOffVideosWithNothingDownloadedAsksNothing() throws {
        let (app, toggle) = launchWithVideoDownloads(cache: "empty")
        flip(toggle)
        expectValue(toggle, "0")
        app.alerts["Turn Off Video Downloads?"].assertStaysAbsent(for: 1.5, "an empty cache asked before turning off")
    }

    @MainActor
    func testCancellingTheVideoAlertKeepsDownloadsOn() throws {
        let (app, toggle) = launchWithVideoDownloads(cache: "seeded")
        flip(toggle)
        XCTAssertTrue(app.alerts["Turn Off Video Downloads?"].waitForExistence(timeout: 5))
        app.alerts.buttons["settings.videos.cancel"].firstMatch.tap()
        XCTAssertTrue(app.alerts["Turn Off Video Downloads?"].waitForNonExistence(timeout: 5))
        expectValue(toggle, "1")
    }

    @MainActor
    func testKeepingVideosTurnsDownloadsOffAndAsksAgainNextTime() throws {
        let (app, toggle) = launchWithVideoDownloads(cache: "seeded")
        flip(toggle)
        XCTAssertTrue(app.alerts["Turn Off Video Downloads?"].waitForExistence(timeout: 5))
        app.alerts.buttons["settings.videos.keep"].firstMatch.tap()
        expectValue(toggle, "0")
        // The kept video is still there: turning on and off again raises the alert once more.
        flip(toggle)
        expectValue(toggle, "1")
        flip(toggle)
        XCTAssertTrue(app.alerts["Turn Off Video Downloads?"].waitForExistence(timeout: 5), "Keep removed the videos")
    }

    @MainActor
    func testRemovingVideosTurnsDownloadsOffAndEmptiesTheCache() throws {
        let (app, toggle) = launchWithVideoDownloads(cache: "seeded")
        flip(toggle)
        XCTAssertTrue(app.alerts["Turn Off Video Downloads?"].waitForExistence(timeout: 5))
        app.alerts.buttons["settings.videos.remove"].firstMatch.tap()
        expectValue(toggle, "0")
        // The cache is empty now: turning on and off again asks nothing.
        flip(toggle)
        expectValue(toggle, "1")
        flip(toggle)
        expectValue(toggle, "0")
        app.alerts["Turn Off Video Downloads?"].assertStaysAbsent(for: 1.5, "Remove left videos behind")
    }

    // MARK: Download progress

    /// With n videos already cached and a slow fixture source, the bar starts at n or more (never at zero), and closing
    /// and reopening Settings does not make it go backwards (PLAN 7b.6; bug 1 of `docs/reviews/2026-11-07-test-gaps.md`).
    @MainActor
    func testDownloadBarStartsAtTheCachedCountAndNeverDecreases() throws {
        let cached = 5
        // The first fetch takes 20 s, longer than the launch + open-Settings + scroll path, so the first read sees the bar
        // before any tick has moved it (200 ms let the first tick hide a bar that started at zero).
        let app = XCUIApplication.launchedForTesting([
            "-mediaSource", "fixture:20000", "-videoCache", "partial:\(cached)", "-downloadAllVideos", "YES",
        ])
        let any = app.descendants(matching: .any)

        /// Opens Settings, scrolls to the Media section and returns the number of videos the bar counts as done.
        func openSettingsAndReadDone() -> Int {
            let gear = any["toolbar.settings"].firstMatch
            XCTAssertTrue(gear.waitForExistence(timeout: 10), "no Settings button")
            gear.tap()
            XCTAssertTrue(any["screen.settings"].waitForExistence(timeout: 5))
            let bar = any["settings.downloadProgress"].firstMatch
            for _ in 0..<5 where !bar.exists { app.swipeUp() }
            XCTAssertTrue(bar.waitForExistence(timeout: 10), "no download progress bar")
            let value = (bar.value as? String) ?? ""
            let done = value.split(separator: " ").first.flatMap { Int($0) }
            XCTAssertNotNil(done, "progress value '\(value)' does not start with a count")
            return done ?? -1
        }

        let first = openSettingsAndReadDone()
        XCTAssertGreaterThanOrEqual(first, cached, "the bar started below the \(cached) cached videos")
        app.buttons["settings.done"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForNonExistence(timeout: 5))

        let second = openSettingsAndReadDone()
        XCTAssertGreaterThanOrEqual(second, first, "the bar went backwards after reopening Settings")
    }

    /// The file pickers cannot be driven reliably, so this only proves the rows exist and Export opens the share sheet
    /// (import, export and re-import are proven by the kit's `ImportExportFlowTests`).
    @MainActor
    func testDataRowsExistAndExportOpensTheShareSheet() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.settings"].waitForExistence(timeout: 10))
        let export = app.buttons["settings.export"].firstMatch
        for _ in 0..<5 where !export.isHittable { app.swipeUp() }
        XCTAssertTrue(export.exists, "no Export row")
        XCTAssertTrue(app.buttons["settings.import"].firstMatch.exists, "no Import row")

        export.tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "no share sheet")
        // Dismiss it with its close button when it exposes one, else by tapping the dimmed area above the sheet.
        let close = app.buttons.matching(NSPredicate(format: "label ==[c] 'close'")).firstMatch
        if close.waitForExistence(timeout: 3) {
            close.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
        }
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10), "share sheet still showing")
        XCTAssertTrue(any["screen.settings"].exists)
    }
}
