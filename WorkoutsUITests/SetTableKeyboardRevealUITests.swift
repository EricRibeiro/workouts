import XCTest

/// Tapping a reps cell in the lower half of the logging screen, keyboard hidden and the table at its bottom, must bring the
/// row clear of the keyboard and the floating keyboard toolbar pill.
final class SetTableKeyboardRevealUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLowerHalfRepsCellIsRevealedAboveKeyboard() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let window = app.windows.firstMatch
        let reps = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.reps'")
        )
        XCTAssertTrue(reps.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        // Scroll the table to its bottom.
        for _ in 0..<10 { app.swipeUp() }

        // The lowest visible reps cell in the lower half of the window.
        let windowFrame = window.frame
        let candidates = reps.allElementsBoundByIndex.filter {
            $0.frame.midY > windowFrame.midY
        }
        let target = try XCTUnwrap(candidates.last, "no hittable reps cell in the lower half")
        let before = target.frame
        let identifier = target.identifier
        target.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let next = app.buttons["setkeyboard.next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        // Let the keyboard avoidance and the reveal scroll settle.
        let cell = app.textFields[identifier]
        let keys = keyboard.waitUntilFrameSettles()
        let pill = next.waitUntilFrameSettles()
        let after = cell.waitUntilFrameSettles()
        let note = "cell before \(before), after \(after), pill \(pill), keyboard \(keys)"
        XCTAssertLessThanOrEqual(after.maxY, pill.minY, "reps cell is under the toolbar pill: \(note)")
        XCTAssertFalse(after.intersects(keys), "reps cell is under the keyboard: \(note)")
    }

    /// Eric's recording: the last row's check dismisses the keyboard, and a tap on the row above while it is still animating
    /// down brings the keyboard back; the row must end up clear of the keyboard and the pill.
    @MainActor
    func testRepsCellTappedDuringCheckDismissalIsRevealed() throws {
        try assertRevealAfterTapDuringDismissal { app, checkID in
            let check = app.switches[checkID].firstMatch
            check.tap()
            return { XCTAssertEqual(check.value as? String, "Done", "the check was refused, so no dismissal ran") }
        }
    }

    /// The same race, with the keyboard dismissed by the toolbar's Done key instead of a check.
    @MainActor
    func testRepsCellTappedDuringDoneDismissalIsRevealed() throws {
        try assertRevealAfterTapDuringDismissal { app, _ in
            app.buttons["setkeyboard.done"].firstMatch.tap()
            return {}
        }
    }

    /// Focuses the last row's reps, runs `dismiss` (which starts the keyboard going down), taps the reps cell above
    /// at once and asserts that cell ends clear of the keyboard and the pill. `dismiss` returns a post-check.
    @MainActor
    private func assertRevealAfterTapDuringDismissal(
        dismiss: (XCUIApplication, String) -> () -> Void
    ) throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let reps = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.reps'")
        )
        XCTAssertTrue(reps.firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<10 { app.swipeUp() }

        // Two fresh unchecked rows at the end of the last block.
        let addSets = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'settable.addset.'"))
        let addSet = try XCTUnwrap(addSets.allElementsBoundByIndex.max { $0.frame.minY < $1.frame.minY })
        addSet.tap()
        addSet.tap()
        for _ in 0..<10 { app.swipeUp() }

        let cells = reps.allElementsBoundByIndex.filter { $0.isHittable }.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertGreaterThanOrEqual(cells.count, 2)
        let lastID = cells[cells.count - 1].identifier
        let aboveID = cells[cells.count - 2].identifier
        let checkID = lastID.replacingOccurrences(of: ".reps", with: ".check")

        // The check refuses an empty row; fill whatever is empty so it is accepted.
        let weightField = app.textFields[lastID.replacingOccurrences(of: ".reps", with: ".weight")]
        if weightField.exists, (weightField.value as? String) == "Empty" {
            weightField.tap()
            weightField.typeText("50")
        }
        let lastReps = app.textFields[lastID]
        lastReps.tap()
        if (lastReps.value as? String) == "Empty" { lastReps.typeText("5") }
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        keyboard.waitUntilFrameSettles()

        let verify = dismiss(app, checkID)
        // No wait: the keyboard is still animating down.
        app.textFields[aboveID].tap()

        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let next = app.buttons["setkeyboard.next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        let keys = keyboard.waitUntilFrameSettles()
        let pill = next.waitUntilFrameSettles()
        let cell = app.textFields[aboveID].waitUntilFrameSettles()
        verify()

        let note = "cell \(cell), pill \(pill), keyboard \(keys), window \(app.windows.firstMatch.frame)"
        XCTContext.runActivity(named: note) { _ in }
        XCTAssertLessThanOrEqual(cell.maxY, pill.minY, "reps cell is under the toolbar pill: \(note)")
        XCTAssertFalse(cell.intersects(keys), "reps cell is under the keyboard: \(note)")
    }
}
