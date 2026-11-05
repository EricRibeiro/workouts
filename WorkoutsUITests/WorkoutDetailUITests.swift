import XCTest

/// The workout detail pushed from the History list on the gallery entry `History` (task 5.5): exercise blocks, Edit (the
/// past editor has its own tests), Save as Template with no folder, and Delete behind a confirmation that pops back to the list.
final class WorkoutDetailUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.row.'")
        )
    }

    /// Launches History and opens the first row (scrolling past the dashboard cards; the list is lazy).
    @MainActor
    private func openFirstWorkout() -> (XCUIApplication, rowID: String) {
        let app = XCUIApplication.launchedPreview("History", waitingFor: "screen.history")
        let any = app.descendants(matching: .any)

        let first = rows(app).element(boundBy: 0)
        for _ in 0..<8 {
            if first.waitForExistence(timeout: 2) && first.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(first.exists, "no history rows")
        let id = first.identifier
        first.tap()
        XCTAssertTrue(any["history.detail"].waitForExistence(timeout: 5), "the row did not open the detail")
        return (app, id)
    }

    @MainActor
    func testDetailShowsTheHeaderAndOneBlockPerExercise() throws {
        let (app, _) = openFirstWorkout()
        let blocks = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'workoutDetail.exercise.'")
        )
        XCTAssertTrue(blocks.element(boundBy: 0).waitForExistence(timeout: 5), "no exercise blocks")
        let label = blocks.element(boundBy: 0).label
        XCTAssertTrue(label.contains("Set 1"), label)
        XCTAssertTrue(app.descendants(matching: .any)["workoutDetail.header"].exists)
        for id in ["workoutDetail.edit", "workoutDetail.saveTemplate", "workoutDetail.delete"] {
            XCTAssertTrue(app.buttons[id].exists, "no toolbar item \(id)")
        }
    }

    @MainActor
    func testEditPushesThePastEditorAndCancelReturns() throws {
        let (app, _) = openFirstWorkout()
        let any = app.descendants(matching: .any)
        app.buttons["workoutDetail.edit"].tap()
        XCTAssertTrue(any["screen.pastEditor"].waitForExistence(timeout: 5), "no past editor")
        // Nothing changed, so Cancel leaves without asking.
        app.buttons["pastEditor.cancel"].tap()
        XCTAssertTrue(any["history.detail"].waitForExistence(timeout: 5), "Cancel did not return to the detail")
    }

    @MainActor
    func testSaveAsTemplateWithNoFolderClosesTheSheet() throws {
        let (app, _) = openFirstWorkout()
        let any = app.descendants(matching: .any)
        app.buttons["workoutDetail.saveTemplate"].tap()
        XCTAssertTrue(any["workoutDetail.saveTemplate.sheet"].waitForExistence(timeout: 5), "no template sheet")

        let none = app.buttons["workoutDetail.saveTemplate.folder.none"]
        XCTAssertTrue(none.waitForExistence(timeout: 5), "no No Folder row")
        none.tap()
        app.buttons["workoutDetail.saveTemplate.confirm"].tap()

        XCTAssertTrue(
            any["workoutDetail.saveTemplate.sheet"].waitUntilGone(timeout: 5),
            "the template sheet did not close"
        )
        XCTAssertTrue(any["history.detail"].exists, "saving a template left the detail")
    }

    @MainActor
    func testDeleteAsksFirstThenPopsBackToTheList() throws {
        let (app, rowID) = openFirstWorkout()
        let any = app.descendants(matching: .any)
        app.buttons["workoutDetail.delete"].tap()
        let confirm = app.buttons["Delete Workout"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no confirmation")
        XCTAssertTrue(any["history.detail"].exists, "the detail left before the confirmation")
        confirm.tap()

        XCTAssertTrue(any["history.detail"].waitUntilGone(timeout: 8), "Delete did not pop the detail")
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            any.matching(identifier: rowID).firstMatch.waitUntilGone(timeout: 5),
            "the deleted row is still listed"
        )
    }
}
