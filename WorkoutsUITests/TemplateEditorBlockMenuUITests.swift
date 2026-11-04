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
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-seedSampleData"]
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workout.template.'")).firstMatch
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

    private func waitUntilGone(_ element: XCUIElement, _ message: String) {
        let gone = NSPredicate(format: "exists == false")
        let closed = XCTNSPredicateExpectation(predicate: gone, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 10), .completed, message)
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
    func testAddWarmupSetsGrowsTheBlockOrAsksForAWeight() throws {
        let app = launchEditor()
        let (menu, section) = firstMenu(app)
        let before = weightFieldCount(in: app, section: section)

        menu.tap()
        let warmup = app.buttons["settable.menu.warmup"].firstMatch
        XCTAssertTrue(warmup.waitForExistence(timeout: 5), "no Add Warm-up Sets entry")
        warmup.tap()

        let alert = app.alerts["Add a working weight first"]
        if alert.waitForExistence(timeout: 3) {
            alert.buttons["OK"].tap()
            XCTAssertEqual(weightFieldCount(in: app, section: section), before, "the alert case changed the block")
        } else {
            let grew = NSPredicate { _, _ in self.weightFieldCount(in: app, section: section) > before }
            let expectation = XCTNSPredicateExpectation(predicate: grew, object: nil)
            XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed, "no warm-up rows were added")
        }
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
        waitUntilGone(block, "the block's header is still there after confirming")

        app.buttons["templateEditor.cancel"].tap()
        let discard = app.buttons["Discard Changes"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "no unsaved-changes dialog")
        discard.tap()
        waitUntilGone(any["screen.templateEditor"], "Discard did not close the editor")
    }
}
