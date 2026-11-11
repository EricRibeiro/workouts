import XCTest

/// The logging cover on the open Duo (PLAN 7c.11): `DEV_POSE=open-wide ./dev ui-test OpenPoseUITests` opens the hinge before
/// launch and restores closed-portrait afterwards. Out of the normal suites: it skips itself unless the runner sees
/// `DUO_POSE=open-wide`, so the full `./dev ui-test` counts its tests as skipped.
///
/// No rotation test: on the open inner display `XCUIDevice.shared.orientation = .landscapeLeft` leaves the window at 951×669
/// and the pane where it was (spike, 2026-11-09), so a placement change cannot be driven from XCUITest.
final class OpenPoseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["DUO_POSE"] != "open-wide",
            "run with DEV_POSE=open-wide ./dev ui-test OpenPoseUITests"
        )
    }

    @MainActor
    func testOpenWideShowsThePaneBesideTheTable() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(window.width, 951, accuracy: 1)
        XCTAssertEqual(window.height, 669, accuracy: 1)

        let pane = app.descendants(matching: .any)["cover.exercisePane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 10))
        let paneFrame = pane.waitUntilFrameSettles()
        // The pane starts at the middle of the safe area, not of the window: the system strip (clock, toolbar) takes about
        // 85 pt of the trailing edge, so the split sits near 433 pt.
        XCTAssertGreaterThanOrEqual(paneFrame.minX, 420, "pane \(paneFrame) is not beside the table")
        XCTAssertEqual(paneFrame.maxX, window.maxX, accuracy: 1)

        let weights = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.weight'")
        )
        XCTAssertTrue(weights.firstMatch.waitForExistence(timeout: 10))
        for cell in weights.allElementsBoundByIndex where cell.exists {
            XCTAssertLessThanOrEqual(
                cell.frame.maxX,
                paneFrame.minX + 1,
                "set table cell \(cell.frame) reaches into the pane"
            )
        }
    }

    /// The Workout tab's two sample folders flow side by side on the open Duo: headers at the same height, the second one
    /// right of the display's middle (the fold).
    @MainActor
    func testOpenWideFoldersSitSideBySide() throws {
        let app = XCUIApplication.launchedPreview("Workout", waitingFor: "screen.workout")
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(window.width, 951, accuracy: 1)

        let headers = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'workout.folder.' AND identifier ENDSWITH '.toggle'")
        )
        XCTAssertTrue(headers.element(boundBy: 1).waitForExistence(timeout: 10), "fewer than two folders")
        let first = headers.element(boundBy: 0).waitUntilFrameSettles()
        let second = headers.element(boundBy: 1).waitUntilFrameSettles()
        XCTAssertEqual(first.minY, second.minY, accuracy: 2, "headers \(first) and \(second) are not side by side")
        XCTAssertGreaterThan(second.minX, window.midX, "second folder \(second) is not right of the fold")
        XCTAssertLessThan(first.maxX, window.midX, "first folder \(first) reaches the fold")
    }

    /// The Exercises tab on the open Duo ends its list on the fold and starts the detail after it, so the exercise video and
    /// text are never cut by the hinge (the fold gutter is about 40 pt wide, centred on the window's middle).
    @MainActor
    func testOpenWideExercisesListEndsAtTheFold() throws {
        let app = XCUIApplication.launchedPreview("Exercises", waitingFor: "screen.exercises")
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(window.width, 951, accuracy: 1)

        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'exercises.row.'")
        )
        let first = rows.element(boundBy: 0)
        XCTAssertTrue(first.waitForExistence(timeout: 10), "no exercise rows")
        first.tap()

        let title = app.descendants(matching: .any)["exerciseDetail.name"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the detail did not open")
        let row = first.waitUntilFrameSettles()
        let detail = title.waitUntilFrameSettles()
        XCTAssertLessThanOrEqual(row.maxX, window.midX + 2, "list row \(row) reaches the fold")
        XCTAssertGreaterThanOrEqual(detail.minX, window.midX - 2, "detail title \(detail) starts before the fold")

        // The list must not be drawn over the detail: its row never intersects the detail's title or segments, and the
        // detail is hittable (an overlaid, dimmed detail is not).
        let about = app.buttons["About"].firstMatch
        XCTAssertTrue(about.waitForExistence(timeout: 5), "the detail's About segment is missing")
        let aboutFrame = about.waitUntilFrameSettles()
        XCTAssertTrue(title.isHittable, "detail title is covered")
        XCTAssertTrue(about.isHittable, "detail About segment is covered")
        XCTAssertFalse(row.intersects(detail), "list row \(row) overlaps the detail title \(detail)")
        XCTAssertFalse(row.intersects(aboutFrame), "list row \(row) overlaps the About segment \(aboutFrame)")
        XCTAssertLessThanOrEqual(row.maxX, detail.minX, "list row \(row) ends after the detail title \(detail) starts")
    }

    /// One audit pass of the open logging cover, with `AccessibilityAuditUITests`' known-issue filter.
    @MainActor
    func testOpenWideLoggingAudit() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        XCTAssertTrue(app.descendants(matching: .any)["cover.exercisePane"].waitForExistence(timeout: 10))
        let context = AccessibilityAuditUITests.Context(behindModal: true, truncatesExerciseNames: true)
        try AccessibilityAuditUITests.audit(app, in: self, for: .all, context)
    }
}
