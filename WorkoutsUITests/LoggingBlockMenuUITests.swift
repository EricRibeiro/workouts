import XCTest

/// The logging screen's per-exercise header menu (task 3.6d), backed by the engine: Remove Exercise asks first and drops the
/// block, and Superset… groups two blocks. The launch is that of `TitleMenuUITests`.
final class LoggingBlockMenuUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchCover() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-startSampleWorkout", "-openWorkoutCover"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.activeWorkout"].waitForExistence(timeout: 15))
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

    private func openMenuEntry(_ app: XCUIApplication, menu: XCUIElement, entry: String) {
        menu.tap()
        let item = app.buttons[entry].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no \(entry) entry")
        item.tap()
    }

    @MainActor
    func testRemoveExerciseConfirmsThenDropsTheBlock() throws {
        let app = launchCover()
        let any = app.descendants(matching: .any)
        let (menu, section) = firstMenu(app)
        let block = any["settable.section.\(section)"]
        XCTAssertTrue(block.exists)

        openMenuEntry(app, menu: menu, entry: "settable.menu.remove")
        let confirm = app.buttons["cover.remove.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no confirmation before removing")
        XCTAssertTrue(block.exists, "the block went before the answer")
        confirm.tap()
        waitUntilGone(block, "the block's header is still there after confirming")
    }

    @MainActor
    func testSupersetGroupsTwoBlocks() throws {
        let app = launchCover()
        let any = app.descendants(matching: .any)
        let (menu, section) = firstMenu(app)
        XCTAssertFalse(any["settable.superset.\(section)"].exists, "the first block starts in a superset")

        openMenuEntry(app, menu: menu, entry: "settable.menu.superset")
        XCTAssertTrue(any["superset.sheet"].waitForExistence(timeout: 5), "no superset sheet")
        let others = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'superset.row.' AND NOT identifier ENDSWITH %@", section)
        )
        XCTAssertGreaterThan(others.count, 0, "the workout has only one block")
        let second = others.element(boundBy: 0)
        let secondID = String(second.identifier.dropFirst("superset.row.".count))
        second.tap()
        let save = app.buttons["superset.save"]
        XCTAssertTrue(save.isEnabled, "ticking a second block did not enable Create Superset")
        save.tap()
        waitUntilGone(any["superset.sheet"], "Create Superset did not close the sheet")
        XCTAssertTrue(
            any["settable.superset.\(section)"].waitForExistence(timeout: 5),
            "first header has no superset marker"
        )
        XCTAssertTrue(
            any["settable.superset.\(secondID)"].waitForExistence(timeout: 5),
            "second header has no superset marker"
        )
    }

    @MainActor
    func testNameOpensExerciseSheetAndHeaderHasNoRestCaption() throws {
        let app = launchCover()
        let any = app.descendants(matching: .any)
        let (_, section) = firstMenu(app)
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Rest '")).count,
            0,
            "the active workout still shows a rest caption under the name"
        )

        let name = app.buttons["settable.name.\(section)"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        XCTAssertTrue(any["screen.exerciseDetail"].waitForExistence(timeout: 10), "tapping the name opened no detail")
        let done = app.buttons["exerciseInfo.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        waitUntilGone(any["screen.exerciseDetail"], "Done did not close the exercise sheet")

        // The block menu's Exercise Info entry opens the same sheet.
        let (menu, _) = firstMenu(app)
        openMenuEntry(app, menu: menu, entry: "settable.menu.info")
        XCTAssertTrue(any["screen.exerciseDetail"].waitForExistence(timeout: 10), "Exercise Info opened no detail")
        app.buttons["exerciseInfo.done"].tap()
        waitUntilGone(any["screen.exerciseDetail"], "Done did not close the exercise sheet")
    }
}
