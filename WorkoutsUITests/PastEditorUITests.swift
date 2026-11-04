import XCTest

/// The past-workout editor (task 5.6) pushed from the first History row's detail on the gallery entry `History`: a weight
/// edit saves and shows in the detail; the same edit cancelled behind the unsaved-changes dialog leaves it alone.
final class PastEditorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches History, opens the first row and returns the app and its first exercise block.
    @MainActor
    private func openFirstWorkout() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-preview", "History"]
        app.launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 10))
        let rows = any.matching(NSPredicate(format: "identifier BEGINSWITH 'history.row.'"))
        let first = rows.element(boundBy: 0)
        for _ in 0..<8 {
            if first.waitForExistence(timeout: 2) && first.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(first.exists, "no history rows")
        first.tap()
        XCTAssertTrue(any["history.detail"].waitForExistence(timeout: 5), "the row did not open the detail")
        return app
    }

    private func firstBlockLabel(_ app: XCUIApplication) -> String {
        let blocks = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'workoutDetail.exercise.'")
        )
        let block = blocks.element(boundBy: 0)
        XCTAssertTrue(block.waitForExistence(timeout: 5), "no exercise blocks")
        return block.label
    }

    /// Opens the editor and steps the first weight field up once with the keyboard's +step; returns the new text.
    @MainActor
    private func editFirstWeight(_ app: XCUIApplication) -> String {
        let any = app.descendants(matching: .any)
        app.buttons["workoutDetail.edit"].tap()
        XCTAssertTrue(any["screen.pastEditor"].waitForExistence(timeout: 5), "no past editor")
        XCTAssertTrue(any["pastEditor.start"].exists, "no start picker")
        XCTAssertTrue(any["pastEditor.duration"].exists, "no duration stepper")
        XCTAssertFalse(app.buttons["pastEditor.save"].isEnabled, "Save is enabled with nothing changed")

        let weight = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.weight'")
        )
        .element(boundBy: 0)
        XCTAssertTrue(weight.waitForExistence(timeout: 5), "no weight field")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "setkeyboard.previous").count, 0)
        let before = (weight.value as? String) ?? ""
        weight.tap()
        let plus = app.buttons["setkeyboard.plus"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "keyboard group missing")
        plus.tap()
        let after = (weight.value as? String) ?? ""
        XCTAssertNotEqual(before, after, "the step did not change the weight")
        app.buttons["setkeyboard.done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["pastEditor.save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pastEditor.save"].isEnabled, "Save is disabled after an edit")
        return after
    }

    @MainActor
    func testEditingAWeightAndSavingShowsItInTheDetail() throws {
        let app = openFirstWorkout()
        let any = app.descendants(matching: .any)
        let before = firstBlockLabel(app)
        let newWeight = editFirstWeight(app)

        app.buttons["pastEditor.save"].tap()
        XCTAssertTrue(any["history.detail"].waitForExistence(timeout: 5), "Save did not return to the detail")
        let gone = NSPredicate(format: "exists == false")
        let closed = XCTNSPredicateExpectation(predicate: gone, object: any["screen.pastEditor"])
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed, "the editor is still up")

        let after = firstBlockLabel(app)
        // The detail shows the display unit (kg 72.5 reads as lb), so the proof is that it changed and that reopening the
        // editor reads the saved value back.
        XCTAssertNotEqual(before, after, "the detail did not change")
        app.buttons["workoutDetail.edit"].tap()
        XCTAssertTrue(any["screen.pastEditor"].waitForExistence(timeout: 5))
        let weight = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.weight'")
        )
        .element(boundBy: 0)
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertEqual(weight.value as? String, newWeight, "the saved weight was not read back")
    }

    @MainActor
    func testCancellingAsksFirstAndDiscardLeavesTheWorkoutAlone() throws {
        let app = openFirstWorkout()
        let any = app.descendants(matching: .any)
        let before = firstBlockLabel(app)
        _ = editFirstWeight(app)

        app.buttons["pastEditor.cancel"].tap()
        let discard = app.buttons["Discard Changes"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "no unsaved-changes dialog")
        XCTAssertTrue(any["screen.pastEditor"].exists, "the editor left before the answer")
        discard.tap()

        XCTAssertTrue(any["history.detail"].waitForExistence(timeout: 5), "Discard did not return to the detail")
        let gone = NSPredicate(format: "exists == false")
        let closed = XCTNSPredicateExpectation(predicate: gone, object: any["screen.pastEditor"])
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed, "the editor is still up")
        XCTAssertEqual(firstBlockLabel(app), before, "a discarded edit changed the workout")
    }
}
