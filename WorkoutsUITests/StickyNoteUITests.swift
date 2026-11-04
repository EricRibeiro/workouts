import XCTest

/// The sticky note (task 4.5): add from the exercise detail, see it, then edit and remove it.
final class StickyNoteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddEditRemoveStickyNote() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-preview", "Exercises"]
        app.launch()

        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.exercises"].waitForExistence(timeout: 10))
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'exercises.row.'")
        )
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 10), "no exercise rows")

        // On the closed Duo the system folds search into a button in the trailing strip; tap it to get the field.
        let search = app.searchFields.firstMatch
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
        XCTAssertTrue(any["screen.exerciseDetail"].waitForExistence(timeout: 5), "the detail did not open")

        // The sample data gives Barbell Bench Press a note; remove it so the flow starts from none.
        let edit = app.buttons["exerciseDetail.stickyNote.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "no sticky note button")
        XCTAssertEqual(edit.label, "Edit Sticky Note")
        edit.tap()
        XCTAssertTrue(app.buttons["stickyNote.remove"].waitForExistence(timeout: 5))
        app.buttons["stickyNote.remove"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: any["exerciseDetail.stickyNote.text"])
        waitForExpectations(timeout: 5)

        // Add.
        XCTAssertEqual(edit.label, "Add Sticky Note")
        XCTAssertFalse(any["exerciseDetail.stickyNote.text"].exists)
        edit.tap()
        let field = app.textViews["stickyNote.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the editor did not open")
        XCTAssertFalse(app.buttons["stickyNote.remove"].exists, "Remove shown with no note")
        field.tap()
        field.typeText("Elbows in")
        app.buttons["stickyNote.save"].tap()

        let text = any["exerciseDetail.stickyNote.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5), "the note is not shown")
        XCTAssertTrue(text.label.contains("Elbows in"), "label was \(text.label)")
        XCTAssertEqual(app.buttons["exerciseDetail.stickyNote.edit"].label, "Edit Sticky Note")

        // Edit, then remove.
        app.buttons["exerciseDetail.stickyNote.edit"].tap()
        XCTAssertTrue(app.textViews["stickyNote.text"].waitForExistence(timeout: 5))
        let remove = app.buttons["stickyNote.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "no Remove button on an existing note")
        remove.tap()

        expectation(for: gone, evaluatedWith: any["exerciseDetail.stickyNote.text"])
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.buttons["exerciseDetail.stickyNote.edit"].label, "Add Sticky Note")
    }
}
