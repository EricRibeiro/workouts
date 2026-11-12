import XCTest

/// A tap on the logging table puts the set keypad away; a tap on another cell keeps it and moves the focus.
final class SetKeypadDismissUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func cells(_ app: XCUIApplication, _ column: String) -> XCUIElementQuery {
        app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.\(column)'")
        )
    }

    private func hasFocus(_ element: XCUIElement) -> Bool {
        element.exists && (element.value(forKey: "hasKeyboardFocus") as? Bool ?? false)
    }

    @MainActor
    func testTapOnTheTablePutsTheKeypadAway() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let weight = cells(app, "weight").firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 10))
        weight.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        _ = weight.waitUntilFrameSettles()

        // The block's column header sits just above its first row.
        weight.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -15)).tap()

        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 6), "the keypad stayed up after a tap on the table")
        keyboard.assertStaysAbsent(for: 3, "the keypad came back")
    }

    @MainActor
    func testTapOnAnotherCellKeepsTheKeypad() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let weight = cells(app, "weight").firstMatch
        let reps = cells(app, "reps").firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 10))
        weight.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(hasFocus(weight))

        reps.tap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(keyboard.exists, "the keypad went away on a tap from one cell to another")
        XCTAssertTrue(hasFocus(reps), "focus did not move to the reps cell")

        // The cell's edge, outside the text itself, still belongs to the cell.
        weight.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(keyboard.exists, "the keypad went away on a tap on a cell's edge")
        XCTAssertTrue(hasFocus(weight), "focus did not move to the weight cell")
        reps.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(keyboard.exists, "the keypad went away on a tap on a cell's side")
        XCTAssertTrue(hasFocus(reps), "focus did not move to the reps cell from its side")
    }
}
