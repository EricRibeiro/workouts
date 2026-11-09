import XCTest

/// The template editor's per-exercise header menu (task 3.6): Add Warm-up Sets grows the block (or says a working weight is
/// needed), Remove Exercise asks first and drops the block, and Cancel then Discard Changes leaves the template alone. The
/// launch and navigation are those of `TemplateEditorUITests`.
final class TemplateEditorBlockMenuUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchEditor() -> XCUIApplication {
        let app = XCUIApplication.launchedForTesting(["-seedSampleData"])
        let card = app.firstTemplateCard
        XCTAssertTrue(card.waitForExistence(timeout: 10), "no template cards")
        card.tap()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["template.preview"].waitForExistence(timeout: 5))
        let edit = app.buttons["template.edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "no Edit item in the preview")
        edit.tap()
        XCTAssertTrue(any["screen.templateEditor"].waitForExistence(timeout: 10), "Edit did not push the editor")
        return app
    }

    /// The first block's options menu button and its section id.
    @MainActor
    private func firstMenu(_ app: XCUIApplication) -> (button: XCUIElement, sectionID: String) {
        let menu = app.buttons.matching(
            NSPredicate(format: "identifier MATCHES '^settable\\\\.menu\\\\.[0-9A-Fa-f-]{36}$'")
        ).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no block menu")
        return (menu, String(menu.identifier.dropFirst("settable.menu.".count)))
    }

    private func weightFieldCount(in app: XCUIApplication, section: String) -> Int {
        app.descendants(matching: .any)["settable.section.\(section)"].textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.weight'")
        ).count
    }

    @MainActor
    func testAddWarmupSetsGrowsTheBlock() throws {
        let app = launchEditor()
        let (menu, section) = firstMenu(app)
        let before = weightFieldCount(in: app, section: section)

        menu.tap()
        let warmup = app.buttons["settable.menu.warmup"].firstMatch
        XCTAssertTrue(warmup.waitForExistence(timeout: 5), "no Add Warm-up Sets entry")
        warmup.tap()

        // The seeded template's first block is a weighted barbell lift (SampleData), so the ramp is built: no alert, and the
        // ramp (bar, 40%, 60%, 80%) is longer than the two seeded warm-ups it replaces.
        XCTAssertFalse(
            app.alerts["Add a working weight first"].waitForExistence(timeout: 2),
            "unexpected no-weight alert"
        )
        let grew = NSPredicate { _, _ in self.weightFieldCount(in: app, section: section) > before }
        let expectation = XCTNSPredicateExpectation(predicate: grew, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed, "no warm-up rows were added")
    }

    @MainActor
    func testRemoveExerciseConfirmsThenDropsTheBlockAndDiscardLeavesTheTemplate() throws {
        let app = launchEditor()
        let any = app.descendants(matching: .any)
        let (menu, section) = firstMenu(app)
        let block = any["settable.section.\(section)"]
        XCTAssertTrue(block.exists)

        menu.tap()
        let remove = app.buttons["settable.menu.remove"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "no Remove Exercise entry")
        remove.tap()
        let confirm = app.buttons["templateEditor.remove.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no confirmation before removing")
        XCTAssertTrue(block.exists, "the block went before the answer")
        confirm.tap()
        XCTAssertTrue(block.waitUntilGone(), "the block's header is still there after confirming")

        app.buttons["templateEditor.cancel"].tap()
        let discard = app.buttons["Discard Changes"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "no unsaved-changes dialog")
        discard.tap()
        XCTAssertTrue(any["screen.templateEditor"].waitUntilGone(), "Discard did not close the editor")
    }

    private func openMenuEntry(_ app: XCUIApplication, menu: XCUIElement, entry: String) {
        menu.tap()
        let item = app.buttons[entry].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no \(entry) entry")
        item.tap()
    }

    @MainActor
    func testSupersetSheetGroupsTwoBlocksAndRemoveUngroups() throws {
        let app = launchEditor()
        let any = app.descendants(matching: .any)
        let (menu, section) = firstMenu(app)
        XCTAssertFalse(any["settable.superset.\(section)"].exists, "the first block starts in a superset")

        openMenuEntry(app, menu: menu, entry: "settable.menu.superset")
        XCTAssertTrue(any["superset.sheet"].waitForExistence(timeout: 5), "no superset sheet")
        let save = app.buttons["superset.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertEqual(save.label, "Create Superset")
        XCTAssertFalse(save.isEnabled, "Create Superset is enabled with one member")
        XCTAssertFalse(app.buttons["superset.remove"].exists, "Remove from Superset shows for a block in none")
        XCTAssertFalse(app.buttons["superset.row.\(section)"].isEnabled, "the current block's row is not locked")

        let others = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'superset.row.' AND NOT identifier ENDSWITH %@", section)
        )
        XCTAssertGreaterThan(others.count, 0)
        let second = others.element(boundBy: 0)
        let secondID = String(second.identifier.dropFirst("superset.row.".count))
        second.tap()
        XCTAssertTrue(save.isEnabled, "ticking a second block did not enable Create Superset")
        save.tap()
        XCTAssertTrue(any["superset.sheet"].waitUntilGone(), "Create Superset did not close the sheet")
        XCTAssertTrue(
            any["settable.superset.\(section)"].waitForExistence(timeout: 5),
            "first header has no superset marker"
        )
        XCTAssertTrue(
            any["settable.superset.\(secondID)"].waitForExistence(timeout: 5),
            "second header has no superset marker"
        )

        // The block is in a group now: Update Superset, with Remove from Superset.
        openMenuEntry(app, menu: menu, entry: "settable.menu.superset")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertEqual(save.label, "Update Superset")
        let remove = app.buttons["superset.remove"]
        // Long sample names make the member list taller, so the button can sit below the fold of the sheet's List.
        if !remove.waitForExistence(timeout: 2) { any["superset.sheet"].swipeUp() }
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "no Remove from Superset")
        remove.tap()
        XCTAssertTrue(
            any["settable.superset.\(section)"].waitUntilGone(),
            "the marker stayed after Remove from Superset"
        )
        XCTAssertTrue(
            any["settable.superset.\(secondID)"].waitUntilGone(),
            "the other member kept its marker (a one-member group dissolves)"
        )
    }

    @MainActor
    func testPreferencesSaveChangesTheUnitAndCancelDoesNot() throws {
        let app = launchEditor()
        let any = app.descendants(matching: .any)
        let (menu, _) = firstMenu(app)
        // The column header is hidden from accessibility, so the proof is what the sheet shows when reopened. Seeded
        // blocks are kg.
        func unitControl() -> XCUIElement { app.segmentedControls["preferences.unit"] }

        openMenuEntry(app, menu: menu, entry: "settable.menu.preferences")
        XCTAssertTrue(any["preferences.sheet"].waitForExistence(timeout: 5), "no preferences sheet")
        XCTAssertTrue(unitControl().waitForExistence(timeout: 5), "no unit picker")
        XCTAssertTrue(unitControl().buttons["kg"].isSelected, "the seeded block is not kg")
        XCTAssertTrue(app.buttons["preferences.bar"].exists, "no bar picker")
        XCTAssertFalse(app.buttons["preferences.rest"].exists, "rest is edited through Update Rest Timer only")
        unitControl().buttons["lb"].tap()
        app.buttons["preferences.cancel"].tap()
        XCTAssertTrue(any["preferences.sheet"].waitUntilGone(), "Cancel did not close the sheet")

        openMenuEntry(app, menu: menu, entry: "settable.menu.preferences")
        XCTAssertTrue(unitControl().waitForExistence(timeout: 5))
        XCTAssertTrue(unitControl().buttons["kg"].isSelected, "Cancel kept the unit change")
        unitControl().buttons["lb"].tap()
        app.buttons["preferences.save"].tap()
        XCTAssertTrue(any["preferences.sheet"].waitUntilGone(), "Save did not close the sheet")

        openMenuEntry(app, menu: menu, entry: "settable.menu.preferences")
        XCTAssertTrue(unitControl().waitForExistence(timeout: 5))
        XCTAssertTrue(unitControl().buttons["lb"].isSelected, "Save did not keep the unit change")
        app.buttons["preferences.cancel"].tap()
    }

    /// Note… in the template editor's block menu opens the note sheet (auto-focused, so the typed text lands
    /// at once); Save closes it and the text shows under the header.
    @MainActor
    func testBlockNoteOpensTheNoteSheetAndShows() throws {
        let app = launchEditor()
        let any = app.descendants(matching: .any)
        let (menu, section) = firstMenu(app)

        openMenuEntry(app, menu: menu, entry: "settable.menu.note")
        XCTAssertTrue(any["templateEditor.note.sheet"].waitForExistence(timeout: 5), "no note sheet")
        let noteField = any["templateEditor.note.field"].firstMatch
        XCTAssertTrue(noteField.waitForExistence(timeout: 5), "no note field")
        XCTAssertFalse(any["templateEditor.note.remove"].exists, "Remove on a block note")
        noteField.typeText(" Pause on the chest.")
        app.buttons["templateEditor.note.save"].tap()
        XCTAssertTrue(any["templateEditor.note.sheet"].waitUntilGone(), "Save did not close the note sheet")
        let note = any["settable.note.\(section)"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "the block note is not shown")
        XCTAssertTrue(note.label.contains("Pause on the chest."), "label was \(note.label)")
    }

    /// Reorder Exercises… in the block menu opens the same reorder sheet as the title menu; Done closes it.
    @MainActor
    func testBlockMenuReorderOpensTheReorderSheet() throws {
        let app = launchEditor()
        let any = app.descendants(matching: .any)
        let (menu, _) = firstMenu(app)

        openMenuEntry(app, menu: menu, entry: "settable.menu.reorder")
        let rows = any.matching(NSPredicate(format: "identifier BEGINSWITH 'reorder.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "the reorder sheet lists no exercises")
        XCTAssertGreaterThanOrEqual(rows.count, 2, "the reorder sheet lists fewer than two exercises")
        app.buttons["reorder.done"].tap()
        XCTAssertTrue(rows.firstMatch.waitUntilGone(), "Done did not close the reorder sheet")
    }
}
