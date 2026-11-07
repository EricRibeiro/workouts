import XCTest

/// The first frame of each pushed screen (PLAN 7b.4, DECISIONS "Pushed-screen chrome"): with every async load held for
/// 3 s by the DEBUG `-slowLoads` seam, the title and toolbar are already there at the push while the loaded content is
/// not, and the content then arrives. Each assertion before the final wait runs without waiting, so a screen that puts its
/// chrome inside the loaded branch fails here deterministically instead of flaking on timing.
final class FirstFrameUITests: XCTestCase {
    private static let slow = ["-slowLoads", "3000"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.row.'")
        )
    }

    /// History with the loads held: waits out the dashboard summary (the rows come from it), then returns the first row
    /// and the workout name from its label ("name, date, duration, volume[, N PRs]").
    @MainActor
    private func slowHistoryFirstRow() throws -> (XCUIApplication, row: XCUIElement, name: String) {
        let app = XCUIApplication.launchedPreview(
            "History",
            extraArguments: Self.slow,
            waitingFor: "screen.history"
        )
        let first = rows(app).element(boundBy: 0)
        for _ in 0..<8 {
            if first.waitForExistence(timeout: 6) && first.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(first.exists, "no history rows")
        let name = try XCTUnwrap(first.label.components(separatedBy: ",").first)
        return (app, first, name)
    }

    @MainActor
    func testWorkoutDetailChromeBeforeTheContent() throws {
        let (app, row, name) = try slowHistoryFirstRow()
        let any = app.descendants(matching: .any)
        row.tap()

        app.assertChromeImmediately(
            title: name,
            buttons: ["workoutDetail.edit", "workoutDetail.saveTemplate", "workoutDetail.delete"]
        )
        XCTAssertFalse(any["history.detail"].exists, "the detail's content was there before its load finished")
        XCTAssertTrue(any["history.detail.loading"].exists, "no loading state in the body while the detail loads")
        XCTAssertTrue(any["history.detail"].waitForExistence(timeout: 10), "the detail never loaded")
        app.assertChromeImmediately(title: name, buttons: ["workoutDetail.edit"])
    }

    /// The exercise detail derives its records on a task; the name, the segmented control and the bar are synchronous.
    /// A library exercise's bar has no title and no buttons, so the chrome here is the body that does not wait.
    @MainActor
    func testExerciseDetailBodyBeforeTheRecords() throws {
        let app = XCUIApplication.launchedPreview(
            "ExerciseDetail",
            extraArguments: Self.slow + ["-detailSegment", "Records"],
            waitingFor: "screen.exerciseDetail"
        )
        let any = app.descendants(matching: .any)

        XCTAssertTrue(any["exerciseDetail.name"].exists, "no exercise name at the push")
        XCTAssertEqual(any["exerciseDetail.name"].label, "Barbell Bench Press")
        XCTAssertTrue(app.segmentedControls["exerciseDetail.segment"].exists, "no segmented control at the push")
        XCTAssertFalse(any["exerciseDetail.records.e1rm"].exists, "the records were there before their load finished")
        XCTAssertTrue(any["exerciseDetail.records.e1rm"].waitForExistence(timeout: 10), "the records never loaded")
    }

    /// The preview's title and Edit are synchronous; only "Last performed" waits for the index.
    @MainActor
    func testTemplatePreviewChromeBeforeLastPerformed() throws {
        let app = XCUIApplication.launchedForTesting(["-seedSampleData"] + Self.slow)
        let any = app.descendants(matching: .any)
        let card = app.firstTemplateCard
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let name = card.label.components(separatedBy: ", ").first ?? ""
        card.tap()
        XCTAssertTrue(any["template.preview"].waitForExistence(timeout: 5))

        app.assertChromeImmediately(buttons: ["template.edit", "template.start"])
        XCTAssertEqual(any["template.preview.title"].label, name, "the preview's title was not there at the push")
        XCTAssertFalse(
            any["template.preview.lastPerformed"].exists,
            "last performed was there before its load finished"
        )
        XCTAssertTrue(
            any["template.preview.lastPerformed"].waitForExistence(timeout: 10),
            "last performed never loaded"
        )
    }

    /// The past-workout editor has no async load (its draft is built from the workout in `init`), so there is no loading
    /// state to hold: this checks that its title and Cancel/Save are on the first frame of the presentation anyway, with
    /// the loads around it held.
    @MainActor
    func testPastEditorChromeAtPresentation() throws {
        let (app, row, name) = try slowHistoryFirstRow()
        let any = app.descendants(matching: .any)
        row.press(forDuration: 1.0)
        let edit = app.buttons["history.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "no Edit in the context menu")
        edit.tap()

        XCTAssertTrue(any["screen.pastEditor"].waitForExistence(timeout: 5), "Edit did not open the editor")
        app.assertChromeImmediately(title: name, buttons: ["pastEditor.cancel", "pastEditor.save"])
    }
}
