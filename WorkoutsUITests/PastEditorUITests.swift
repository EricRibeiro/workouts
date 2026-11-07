import XCTest

/// The past-workout editor (task 5.6) presented (a full-screen cover) from the first History row's detail on the gallery entry `History`: a weight
/// edit saves and shows in the detail; the same edit cancelled behind the unsaved-changes dialog leaves it alone.
final class PastEditorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches History, opens the first row and returns the app and its first exercise block.
    @MainActor
    private func openFirstWorkout() -> XCUIApplication {
        let app = XCUIApplication.launchedPreview("History", waitingFor: "screen.history")
        let any = app.descendants(matching: .any)
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
        XCTAssertTrue(any["pastEditor.duration"].exists, "no duration field")
        XCTAssertTrue(any["pastEditor.duration.stepper"].exists, "no duration stepper")
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
        XCTAssertTrue(any["screen.pastEditor"].waitUntilGone(timeout: 5), "the editor is still up")

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

    /// Opens the editor, then the first block's options menu.
    @MainActor
    private func openFirstBlockMenu(_ app: XCUIApplication) {
        let any = app.descendants(matching: .any)
        app.buttons["workoutDetail.edit"].tap()
        XCTAssertTrue(any["screen.pastEditor"].waitForExistence(timeout: 5), "no past editor")
        let options = app.buttons.matching(NSPredicate(format: "label ENDSWITH ' options'")).element(boundBy: 0)
        XCTAssertTrue(options.waitForExistence(timeout: 5), "no block options menu")
        options.tap()
    }

    @MainActor
    func testBlockMenuOffersOnlyTheNotes() throws {
        let app = openFirstWorkout()
        openFirstBlockMenu(app)
        XCTAssertTrue(app.buttons["settable.menu.note"].waitForExistence(timeout: 5), "no Note…")
        XCTAssertTrue(app.buttons["settable.menu.stickyNote"].exists, "no Sticky Note…")
        for hidden in ["warmup", "rest", "replace", "superset", "preferences", "remove"] {
            XCTAssertFalse(app.buttons["settable.menu.\(hidden)"].exists, "\(hidden) is offered for a finished workout")
        }
    }

    @MainActor
    func testEditingABlockNoteAndSavingShowsItInTheDetail() throws {
        let app = openFirstWorkout()
        let any = app.descendants(matching: .any)
        openFirstBlockMenu(app)
        app.buttons["settable.menu.note"].tap()
        XCTAssertTrue(any["pastEditor.note.sheet"].waitForExistence(timeout: 5), "no note sheet")
        let field = any["pastEditor.note.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no note field")
        field.typeText("Paused reps")
        app.buttons["pastEditor.note.save"].tap()
        XCTAssertTrue(any["pastEditor.note.sheet"].waitUntilGone(), "Save did not close the note sheet")
        XCTAssertTrue(app.buttons["pastEditor.save"].isEnabled, "Save is disabled after a note edit")

        app.buttons["pastEditor.save"].tap()
        XCTAssertTrue(any["history.detail"].waitForExistence(timeout: 5), "Save did not return to the detail")
        XCTAssertTrue(any["screen.pastEditor"].waitUntilGone(timeout: 5), "the editor is still up")
        XCTAssertTrue(
            firstBlockLabel(app).contains("Paused reps"),
            "the detail's first block does not show the note: \(firstBlockLabel(app))"
        )
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
        XCTAssertTrue(any["screen.pastEditor"].waitUntilGone(timeout: 5), "the editor is still up")
        XCTAssertEqual(firstBlockLabel(app), before, "a discarded edit changed the workout")
    }

    @MainActor
    func testDurationTakesTypedMinutesAndTheStepperAdjustsThem() throws {
        let app = openFirstWorkout()
        let any = app.descendants(matching: .any)
        app.buttons["workoutDetail.edit"].tap()
        XCTAssertTrue(any["screen.pastEditor"].waitForExistence(timeout: 5), "no past editor")
        XCTAssertFalse(app.buttons["pastEditor.save"].isEnabled, "Save is enabled with nothing changed")

        let field = app.textFields["pastEditor.duration"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no duration field")
        field.tap()
        field.press(forDuration: 1.0)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) { selectAll.tap() }
        field.typeText("9999")
        let done = app.buttons["pastEditor.duration.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "no Done on the number pad")
        done.tap()
        XCTAssertEqual(field.value as? String, "1,440", "typed minutes were not clamped to a day")
        XCTAssertTrue(app.buttons["pastEditor.save"].isEnabled, "Save is disabled after a duration edit")

        let stepper = app.steppers["pastEditor.duration.stepper"]
        XCTAssertTrue(stepper.exists, "no duration stepper")
        stepper.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(field.value as? String, "1,439", "the stepper did not step the field down")
    }

    /// The editor is modal: an unsaved edit survives a tap on the History tab button (the native reselect pops pushed
    /// screens, which is why the editor is a cover). On the closed Duo the tab bar is behind the cover, so the button is
    /// either not hittable or does nothing; either way the editor and its edit are still there. Needs the whole tab shell.
    @MainActor
    func testTappingTheHistoryTabKeepsAnUnsavedEdit() throws {
        let app = XCUIApplication.launchedPreview("Root")
        let any = app.descendants(matching: .any)
        let tab = any["tab.history"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "no History tab")
        tab.tap()
        let first = any.matching(NSPredicate(format: "identifier BEGINSWITH 'history.row.'")).element(boundBy: 0)
        for _ in 0..<8 {
            if first.waitForExistence(timeout: 2) && first.isHittable { break }
            app.swipeUp()
        }
        first.tap()
        XCTAssertTrue(any["history.detail"].waitForExistence(timeout: 5))
        app.buttons["workoutDetail.edit"].tap()
        XCTAssertTrue(any["screen.pastEditor"].waitForExistence(timeout: 5), "no past editor")
        app.steppers["pastEditor.duration.stepper"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["pastEditor.save"].isEnabled, "Save is disabled after an edit")

        let tabNow = any["tab.history"].firstMatch
        if tabNow.exists && tabNow.isHittable { tabNow.tap() }
        XCTAssertTrue(any["screen.pastEditor"].exists, "the History tab dropped the editor")
        XCTAssertTrue(app.buttons["pastEditor.save"].isEnabled, "the unsaved edit was lost")
    }
}
