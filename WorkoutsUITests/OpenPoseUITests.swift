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

    /// The Workout tab's two sample folders flow side by side on the open Duo: headers at the same height, in two equal
    /// columns across the content width that ignore the flat hinge (the second one starts left of the display's middle).
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
        XCTAssertGreaterThan(second.minX, first.maxX, "second folder \(second) overlaps the first \(first)")
        XCTAssertEqual(
            second.minX,
            window.width * 0.46,
            accuracy: 20,
            "second folder \(second) is not at the second equal column"
        )
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
