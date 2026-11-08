import XCTest

/// The sticky note (task 4.5): add from the exercise detail, see it, then edit and remove it.
final class StickyNoteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddEditRemoveStickyNote() throws {
        let app = XCUIApplication.launchedPreview("Exercises", waitingFor: "screen.exercises")

        let any = app.descendants(matching: .any)
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
        XCTAssertTrue(any["exerciseDetail.stickyNote.text"].waitUntilGone(timeout: 2), "the removed note still shows")
        edit.tap()
        let field = any["stickyNote.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the editor did not open")
        XCTAssertTrue(app.buttons["stickyNote.save"].waitForExistence(timeout: 5), "the editor has no Save")
        app.buttons["stickyNote.remove"].assertStaysAbsent(for: 1, "Remove shown with no note")
        field.tap()
        field.typeText("Elbows in")
        app.buttons["stickyNote.save"].tap()

        let text = any["exerciseDetail.stickyNote.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5), "the note is not shown")
        XCTAssertTrue(text.label.contains("Elbows in"), "label was \(text.label)")
        XCTAssertEqual(app.buttons["exerciseDetail.stickyNote.edit"].label, "Edit Sticky Note")

        // Edit, then remove.
        app.buttons["exerciseDetail.stickyNote.edit"].tap()
        XCTAssertTrue(any["stickyNote.field"].firstMatch.waitForExistence(timeout: 5))
        let remove = app.buttons["stickyNote.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "no Remove button on an existing note")
        remove.tap()

        expectation(for: gone, evaluatedWith: any["exerciseDetail.stickyNote.text"])
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.buttons["exerciseDetail.stickyNote.edit"].label, "Add Sticky Note")

        // The note is About content: the other segments do not show it, and About brings it back.
        let segment = app.segmentedControls["exerciseDetail.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            any["exerciseDetail.stickyNote"].frame.minY,
            segment.frame.maxY,
            "the sticky note is not below the segmented control"
        )
        segment.buttons["History"].tap()
        XCTAssertTrue(any["exerciseDetail.stickyNote"].waitUntilGone(), "the sticky note shows outside About")
        segment.buttons["About"].tap()
        XCTAssertTrue(
            any["exerciseDetail.stickyNote"].waitForExistence(timeout: 5),
            "About did not bring the note back"
        )
    }
}
