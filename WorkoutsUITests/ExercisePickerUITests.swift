import XCTest

/// The exercise picker's multi-select flow on the gallery entry `ExercisePickerMulti`.
final class ExercisePickerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMultiSelectAddSupersetAndPeek() throws {
        let app = XCUIApplication.launchedPreview("ExercisePickerMulti", waitingFor: "screen.exercisePicker")

        let any = app.descendants(matching: .any)

        // Nothing ticked: Add and Superset are disabled.
        let add = any["picker.add"].firstMatch
        let superset = any["picker.superset"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(add.isEnabled)
        XCTAssertFalse(superset.isEnabled)

        // On the closed Duo the system folds search into a button in the trailing strip; tap it to get the field.
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3) {
            let button = app.buttons["Search"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText("squat\n")  // Return dismisses the keyboard, so the toolbar is back

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'picker.row.'"))
        XCTAssertTrue(rows.element(boundBy: 1).waitForExistence(timeout: 5))
        let first = rows.element(boundBy: 0)
        let second = rows.element(boundBy: 1)

        first.tap()
        XCTAssertTrue(first.isSelected)
        second.tap()
        XCTAssertTrue(second.isSelected)

        // An active search hides the toolbar; leave it (the ticked rows are kept) to read Add and Superset.
        if !add.exists {
            let close = app.buttons["close"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            close.tap()
        }
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.label.contains("2"), "Add label was \(add.label)")
        XCTAssertTrue(add.isEnabled)
        XCTAssertTrue(superset.isEnabled)

        // The peek opens over the picker and closes without touching the selection.
        let about = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'picker.about.'")).element(
            boundBy: 0
        )
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.tap()
        XCTAssertTrue(any["screen.exerciseAbout"].waitForExistence(timeout: 5))
        XCTAssertTrue(any["exerciseDetail.name"].exists)
        let close = any["about.close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(any["screen.exercisePicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(any["screen.exerciseAbout"].waitUntilGone(timeout: 5), "the info sheet is still up")
        XCTAssertTrue(add.label.contains("2"))
    }
}
