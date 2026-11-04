import XCTest

/// The template editor (task 3.4): card -> preview -> Edit pushes the editor (a sheet at compact width closes first). A
/// planned weight edit saves and shows in the reopened preview; the same edit cancelled behind the unsaved-changes dialog
/// leaves the template alone; Add Exercise adds a block. These use the real app with the sample data.
final class TemplateEditorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-seedSampleData"]
        app.launch()
        return app
    }

    private func firstCard(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workout.template.'")).firstMatch
    }

    /// The first exercise row's sentence in the open preview (`3 sets of Bench Press, 3 × 100 kg × 5`).
    private func firstPlan(_ app: XCUIApplication) -> String {
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '^[0-9]+ sets? of .*'"))
        let row = rows.element(boundBy: 0)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no exercise rows in the preview")
        return row.label
    }

    /// Opens the first card's preview and returns the title and the first row's plan.
    @MainActor
    private func openPreview(_ app: XCUIApplication) -> String {
        let card = firstCard(app)
        XCTAssertTrue(card.waitForExistence(timeout: 10), "no template cards")
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["template.preview"].waitForExistence(timeout: 5))
        return firstPlan(app)
    }

    @MainActor
    private func openEditor(_ app: XCUIApplication) {
        let edit = app.buttons["template.edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "no Edit item in the preview")
        edit.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["screen.templateEditor"].waitForExistence(timeout: 10),
            "Edit did not push the editor"
        )
    }

    /// Steps the first weight field up once with the keyboard's +step.
    @MainActor
    private func editFirstWeight(_ app: XCUIApplication) {
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
        XCTAssertNotEqual(before, (weight.value as? String) ?? "", "the step did not change the weight")
        app.buttons["setkeyboard.done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["templateEditor.save"].waitForExistence(timeout: 5))
    }

    private func waitUntilGone(_ element: XCUIElement, _ message: String) {
        let gone = NSPredicate(format: "exists == false")
        let closed = XCTNSPredicateExpectation(predicate: gone, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 10), .completed, message)
    }

    @MainActor
    func testEditingAWeightAndSavingShowsItInTheReopenedPreview() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        let before = openPreview(app)
        openEditor(app)
        XCTAssertTrue(app.buttons["templateEditor.cancel"].exists)
        XCTAssertTrue(app.buttons["templateEditor.addExercise"].exists)
        editFirstWeight(app)

        app.buttons["templateEditor.save"].tap()
        waitUntilGone(any["screen.templateEditor"], "Save did not close the editor")

        // Compact: back on the grid (the sheet closed); regular: back on the pushed preview.
        if !any["template.preview"].waitForExistence(timeout: 3) {
            let card = firstCard(app)
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.tap()
            XCTAssertTrue(any["template.preview"].waitForExistence(timeout: 5))
        }
        XCTAssertNotEqual(firstPlan(app), before, "the preview did not show the saved weight")
    }

    @MainActor
    func testBackAsksFirstAndDiscardLeavesTheTemplateAlone() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        let before = openPreview(app)
        openEditor(app)
        editFirstWeight(app)

        app.buttons["templateEditor.cancel"].tap()
        let discard = app.buttons["Discard Changes"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "no unsaved-changes dialog")
        XCTAssertTrue(any["screen.templateEditor"].exists, "the editor left before the answer")
        discard.tap()
        waitUntilGone(any["screen.templateEditor"], "Discard did not close the editor")

        if !any["template.preview"].waitForExistence(timeout: 3) {
            let card = firstCard(app)
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.tap()
            XCTAssertTrue(any["template.preview"].waitForExistence(timeout: 5))
        }
        XCTAssertEqual(firstPlan(app), before, "a discarded edit changed the template")
    }

    @MainActor
    func testCancelWithNothingChangedLeavesWithoutAsking() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        _ = openPreview(app)
        openEditor(app)
        app.buttons["templateEditor.cancel"].tap()
        waitUntilGone(any["screen.templateEditor"], "Cancel did not close the editor")
        XCTAssertFalse(app.buttons["Discard Changes"].exists)
    }

    @MainActor
    func testAddExerciseAddsABlock() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        _ = openPreview(app)
        openEditor(app)
        XCTAssertTrue(any["settable"].waitForExistence(timeout: 5))

        app.buttons["templateEditor.addExercise"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'picker.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no picker rows")
        // The row's label starts with the exercise name.
        let name = row.label.components(separatedBy: ",").first ?? row.label
        row.tap()
        let add = any["picker.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        waitUntilGone(any["picker.add"].firstMatch, "the picker did not close")

        // The new block is last; the table is lazy, so scroll to it.
        let block = any.matching(
            NSPredicate(format: "identifier BEGINSWITH 'settable.name.' AND label CONTAINS %@", name)
        ).firstMatch
        for _ in 0..<12 where !block.exists {
            app.swipeUp()
        }
        XCTAssertTrue(block.exists, "no block for \(name) was added")
    }

    /// Edit Note… in the title menu (the system drops the items' identifiers, so the item is matched by label) opens the
    /// note sheet; the typed text is kept, saved with the template and shown by the reopened preview.
    @MainActor
    func testEditNoteFromTitleMenuSavesAndShowsInThePreview() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        _ = openPreview(app)
        openEditor(app)
        let title = app.navigationBars.buttons.matching(
            NSPredicate(format: "NOT identifier BEGINSWITH 'templateEditor.'")
        )
        .firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "no title menu button")
        title.tap()
        let item = app.buttons.matching(NSPredicate(format: "label == 'Edit Note…'")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no Edit Note item")
        item.tap()

        XCTAssertTrue(any["templateEditor.templateNote.sheet"].waitForExistence(timeout: 5), "no note sheet")
        let field = any["templateEditor.templateNote.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no note field")
        field.typeText(" Heavy singles.")
        app.buttons["templateEditor.templateNote.save"].tap()
        waitUntilGone(any["templateEditor.templateNote.sheet"], "Save did not close the note sheet")

        app.buttons["templateEditor.save"].tap()
        waitUntilGone(any["screen.templateEditor"], "Save did not close the editor")
        if !any["template.preview"].waitForExistence(timeout: 3) {
            let card = firstCard(app)
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.tap()
            XCTAssertTrue(any["template.preview"].waitForExistence(timeout: 5))
        }
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Heavy singles.'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "the preview does not show the edited note")
    }
}
