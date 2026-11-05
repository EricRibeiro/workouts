import XCTest

/// Folders on the Workout tab (task 3.1), on the gallery entry `Workout` (sample folders "Upper Body" and "Lower Body"):
/// collapse, New Folder, Rename, Delete (empty and with templates).
final class FoldersUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.launchedPreview("Workout")
        return app
    }

    private func toggles(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'workout.folder.' AND identifier ENDSWITH '.toggle'")
        )
    }

    private func toggle(_ app: XCUIApplication, named name: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format:
                    "identifier BEGINSWITH 'workout.folder.' AND identifier ENDSWITH '.toggle' AND label BEGINSWITH %@",
                name
            )
        ).firstMatch
    }

    private func templateRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'workout.template.'"))
    }

    @MainActor
    private func openMenu(of header: XCUIElement, _ app: XCUIApplication, item: String) {
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        header.press(forDuration: 1.2)
        let action = app.buttons[item].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), "context menu did not show \(item)")
        action.tap()
    }

    @MainActor
    private func addFolder(_ app: XCUIApplication, named name: String) {
        let add = app.buttons["toolbar.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let new = app.buttons["toolbar.add.newFolder"].firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(name)
        app.alerts.buttons["workout.folderName.confirm"].firstMatch.tap()
    }

    @MainActor
    func testSampleFoldersCollapseAndCreateRenameDelete() throws {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.workout"].waitForExistence(timeout: 10))

        // Sample data: two folders, three templates, headers read "<name> (<count>)".
        let upper = toggle(app, named: "Upper Body")
        XCTAssertTrue(upper.waitForExistence(timeout: 5), "no Upper Body folder")
        XCTAssertTrue(toggle(app, named: "Lower Body").exists)
        expectCount(toggles(app), 2)
        expectCount(templateRows(app), 3)
        XCTAssertEqual(upper.value as? String, "Expanded")

        // Collapsing hides that folder's rows only.
        upper.tap()
        XCTAssertEqual(toggle(app, named: "Upper Body").value as? String, "Collapsed")
        expectCount(templateRows(app), 1, "collapsing Upper Body should leave only Lower Body's template")
        toggle(app, named: "Upper Body").tap()
        expectCount(templateRows(app), 3)

        // New Folder lands last, empty.
        addFolder(app, named: "Mobility")
        let mobility = toggle(app, named: "Mobility")
        XCTAssertTrue(mobility.waitForExistence(timeout: 5), "New Folder did not add a header")
        XCTAssertTrue(mobility.label.contains("0 templates"), mobility.label)
        expectCount(toggles(app), 3)
        XCTAssertEqual(toggles(app).element(boundBy: 2).label.prefix(8), "Mobility")

        // Rename through the header's context menu.
        openMenu(of: mobility, app, item: "workout.folder.rename")
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // typeText taps the field's centre, which can leave the caret mid-text: tap its trailing end first.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Mobility".count) + "Stretching")
        let rename = app.alerts.buttons["workout.folderName.confirm"].firstMatch
        rename.tap()
        // The first tap can be spent accepting the keyboard's autocorrect candidate.
        if app.alerts.firstMatch.waitForExistence(timeout: 1) { rename.tap() }
        let renamed = toggle(app, named: "Stretching")
        XCTAssertTrue(renamed.waitForExistence(timeout: 5), "rename did not show")
        XCTAssertFalse(toggle(app, named: "Mobility").exists)

        // Move Up swaps it with Lower Body.
        openMenu(of: renamed, app, item: "workout.folder.moveUp")
        XCTAssertTrue(
            toggles(app).element(boundBy: 1).label.hasPrefix("Stretching"),
            "Move Up did not reorder: \(toggles(app).element(boundBy: 1).label)"
        )

        // Delete the empty folder: a confirmation, no template choice.
        openMenu(of: toggle(app, named: "Stretching"), app, item: "workout.folder.delete")
        let confirm = app.buttons["workout.folder.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["workout.folder.delete.move"].exists)
        confirm.tap()
        XCTAssertTrue(toggle(app, named: "Stretching").waitUntilGone(timeout: 5), "folder was not deleted")
        expectCount(toggles(app), 2)
        expectCount(templateRows(app), 3)
    }

    @MainActor
    func testDeleteFolderMovesItsTemplatesToUnfiled() throws {
        let app = launch()
        let upper = toggle(app, named: "Upper Body")
        XCTAssertTrue(upper.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["workout.unfiled"].exists)

        openMenu(of: upper, app, item: "workout.folder.delete")
        let move = app.buttons["workout.folder.delete.move"].firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 5), "no Move to Unfiled choice")
        XCTAssertTrue(app.buttons["workout.folder.delete.confirm"].exists)
        move.tap()

        XCTAssertTrue(toggle(app, named: "Upper Body").waitUntilGone(timeout: 5))
        expectCount(templateRows(app), 3, "templates should survive unfiled")
        XCTAssertTrue(app.descendants(matching: .any)["workout.unfiled"].waitForExistence(timeout: 5))
        expectCount(toggles(app), 1)
    }

    @MainActor
    func testDeleteFolderAndItsTemplates() throws {
        let app = launch()
        let upper = toggle(app, named: "Upper Body")
        XCTAssertTrue(upper.waitForExistence(timeout: 10))
        openMenu(of: upper, app, item: "workout.folder.delete")
        let confirm = app.buttons["workout.folder.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(toggle(app, named: "Upper Body").waitUntilGone(timeout: 5))
        expectCount(templateRows(app), 1)
    }

    /// The query reaches `count` within a few seconds (collapse and delete animate).
    @MainActor
    private func expectCount(
        _ query: XCUIElementQuery,
        _ count: Int,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(5)
        while query.count != count && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        XCTAssertEqual(query.count, count, message, file: file, line: line)
    }
}
