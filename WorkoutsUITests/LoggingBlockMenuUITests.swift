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
        let close = app.buttons["exerciseInfo.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))

        // The sheet opens at half height; picking a segment expands it to full height. The Close button sits in the
        // sheet's top corner, so its position is the sheet's top edge.
        let windowHeight = app.windows.firstMatch.frame.height
        let mediumTop = close.frame.minY
        XCTAssertGreaterThan(mediumTop, windowHeight * 0.3, "the sheet did not open at half height")
        let segment = app.segmentedControls["exerciseDetail.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 5))
        segment.buttons["History"].tap()
        // The detent change animates; wait for the Close button to settle well above where it was at half height.
        let deadline = Date().addingTimeInterval(5)
        while close.frame.minY > mediumTop * 0.7 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertLessThan(
            close.frame.minY,
            mediumTop * 0.7,
            "tapping a segment did not expand the sheet to full height (Close at \(close.frame.minY), was \(mediumTop), window \(windowHeight))"
        )
        close.tap()
        waitUntilGone(any["screen.exerciseDetail"], "Close did not close the exercise sheet")

        // The block menu's Exercise Info entry opens the same sheet.
        let (menu, _) = firstMenu(app)
        openMenuEntry(app, menu: menu, entry: "settable.menu.info")
        XCTAssertTrue(any["screen.exerciseDetail"].waitForExistence(timeout: 10), "Exercise Info opened no detail")
        app.buttons["exerciseInfo.close"].tap()
        waitUntilGone(any["screen.exerciseDetail"], "Close did not close the exercise sheet")
    }

    /// A long library name stays on one line in the logging header: its button is about as tall as a short name's.
    @MainActor
    func testLongExerciseNameIsOneLine() throws {
        let app = launchCover()
        let names = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'settable.name.'"))
        let long = names.matching(NSPredicate(format: "label CONTAINS 'Lever Seated Hammer Grip Shoulder Press'"))
            .firstMatch
        let short = names.matching(NSPredicate(format: "label CONTAINS 'Barbell Bench Press'")).firstMatch
        XCTAssertTrue(short.waitForExistence(timeout: 10), "no Barbell Bench Press header")
        XCTAssertTrue(long.waitForExistence(timeout: 10), "no Lever Seated Hammer Grip Shoulder Press header")
        XCTAssertLessThan(
            long.frame.height,
            short.frame.height * 1.5,
            "the long name wraps (\(long.frame.height) vs \(short.frame.height))"
        )
    }
}
