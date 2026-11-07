import XCTest

/// The logging screen's per-exercise header menu (task 3.6d), backed by the engine: Remove Exercise asks first and drops the
/// block, and Superset… groups two blocks. The launch is that of `TitleMenuUITests`.
final class LoggingBlockMenuUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchCover() -> XCUIApplication {
        let app = XCUIApplication.launchedInActiveWorkout()
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
        XCTAssertTrue(block.waitUntilGone(), "the block's header is still there after confirming")
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
        XCTAssertTrue(any["superset.sheet"].waitUntilGone(), "Create Superset did not close the sheet")
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
        let detail = any["screen.exerciseDetail"]

        // The sheet opens at half height; picking a segment expands it to full height. The detail's content starts at
        // the sheet's top edge, so its position tracks the detent.
        let windowHeight = app.windows.firstMatch.frame.height
        let mediumTop = detail.frame.minY
        XCTAssertGreaterThan(mediumTop, windowHeight * 0.3, "the sheet did not open at half height")
        let segment = app.segmentedControls["exerciseDetail.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 5))
        // At the medium detent the segments sit right under the name: on screen and tappable, and the sticky note (when
        // the exercise has one) is About content below them, not between the name and the segments.
        XCTAssertTrue(segment.isHittable, "the segmented control is not hittable at the medium detent")
        XCTAssertLessThan(segment.frame.maxY, windowHeight, "the segmented control is below the medium detent")
        let sticky = any["exerciseDetail.stickyNote"]
        if sticky.exists {
            XCTAssertGreaterThanOrEqual(
                sticky.frame.minY,
                segment.frame.maxY,
                "the sticky note sits between the name and the segmented control"
            )
        }
        segment.buttons["History"].tap()
        // The detent change animates; wait for the sheet to settle well above where it was at half height.
        let deadline = Date().addingTimeInterval(5)
        while detail.frame.minY > mediumTop * 0.7 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertLessThan(
            detail.frame.minY,
            mediumTop * 0.7,
            "tapping a segment did not expand the sheet to full height (top at \(detail.frame.minY), was \(mediumTop), window \(windowHeight))"
        )
        app.dismissSheetBySwiping(top: detail)
        XCTAssertTrue(any["screen.exerciseDetail"].waitUntilGone(), "swiping down did not close the exercise sheet")

        // The block menu's Exercise Info entry opens the same sheet.
        let (menu, _) = firstMenu(app)
        openMenuEntry(app, menu: menu, entry: "settable.menu.info")
        XCTAssertTrue(any["screen.exerciseDetail"].waitForExistence(timeout: 10), "Exercise Info opened no detail")
        app.dismissSheetBySwiping(top: any["screen.exerciseDetail"])
        XCTAssertTrue(any["screen.exerciseDetail"].waitUntilGone(), "swiping down did not close the exercise sheet")
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

    /// Note… and Sticky Note… in the logging screen's block menu open the one note sheet (auto-focused, so the typed text lands
    /// at once); Save closes it and the text shows under the header.
    @MainActor
    func testBlockNoteAndStickyNoteOpenTheNoteSheetAndShow() throws {
        let app = launchCover()
        let any = app.descendants(matching: .any)
        let (menu, section) = firstMenu(app)

        openMenuEntry(app, menu: menu, entry: "settable.menu.note")
        XCTAssertTrue(any["cover.note.sheet"].waitForExistence(timeout: 5), "no note sheet")
        let noteField = any["cover.note.field"].firstMatch
        XCTAssertTrue(noteField.waitForExistence(timeout: 5), "no note field")
        XCTAssertFalse(any["cover.note.remove"].exists, "Remove on a block note")
        noteField.typeText(" Pause on the chest.")
        app.buttons["cover.note.save"].tap()
        XCTAssertTrue(any["cover.note.sheet"].waitUntilGone(), "Save did not close the note sheet")
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Pause on the chest.'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "the block note is not shown")

        openMenuEntry(app, menu: menu, entry: "settable.menu.stickyNote")
        XCTAssertTrue(any["stickyNote.sheet"].waitForExistence(timeout: 5), "no sticky note sheet")
        let stickyField = any["stickyNote.field"].firstMatch
        XCTAssertTrue(stickyField.waitForExistence(timeout: 5), "no sticky note field")
        stickyField.typeText(" Elbows in.")
        app.buttons["stickyNote.save"].tap()
        XCTAssertTrue(any["stickyNote.sheet"].waitUntilGone(), "Save did not close the sticky note sheet")
        let sticky = any["settable.sticky.\(section)"]
        XCTAssertTrue(sticky.waitForExistence(timeout: 5), "the sticky note is not shown")
        XCTAssertTrue(sticky.label.contains("Elbows in."), "label was \(sticky.label)")
    }
}
