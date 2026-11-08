import XCTest

/// Library exercises tagged `isometric` (Plank) are timed by default: their rows carry a Time cell and no weight cell, in the
/// active workout and in the template editor.
final class TimedExerciseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func fields(in container: XCUIElement, ending suffix: String) -> XCUIElementQuery {
        container.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH %@", suffix)
        )
    }

    /// Opens the picker from `addButton`, searches "Plank", ticks the row named exactly "Plank" and adds it.
    @MainActor
    private func addPlank(_ app: XCUIApplication, from addButton: XCUIElement) {
        let any = app.descendants(matching: .any)
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        XCTAssertTrue(any["screen.exercisePicker"].waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3) {
            let button = app.buttons["Search"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText("Plank\n")
        // The row's label starts with the name; "Plank," excludes "Side Plank" and the like.
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'picker.row.' AND label BEGINSWITH 'Plank,'")
        )
        .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no picker row for Plank")
        XCTAssertTrue(waitUntil { row.isHittable }, "the Plank row is not hittable")
        // Rows under the bottom search bar do not take taps; scroll Plank up first.
        let plankRow = app.buttons[row.identifier].firstMatch
        if plankRow.frame.minY > 400 {
            // Drag from the first row: the search bar at the bottom swallows touches on the rows beneath it.
            let top = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'picker.row.'")).firstMatch
            top.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.1))
            )
            XCTAssertTrue(waitUntil { plankRow.exists && plankRow.frame.minY < 450 }, "the list did not scroll")
        }
        plankRow.tap()
        XCTAssertTrue(waitUntil { plankRow.isSelected }, "the Plank row is not ticked (row at \(plankRow.frame))")
        // An active search hides the toolbar; leave it (the ticked row is kept) to reach Add.
        let pickerAdd = any["picker.add"].firstMatch
        if !pickerAdd.isHittable {
            let close = app.buttons["close"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            close.tap()
        }
        XCTAssertTrue(
            waitUntil { pickerAdd.isHittable && pickerAdd.isEnabled },
            "Add is not tappable: \(pickerAdd.label)"
        )
        XCTAssertTrue(pickerAdd.label.contains("1"), "Add label was \(pickerAdd.label)")
        pickerAdd.tap()
        XCTAssertTrue(
            any["screen.exercisePicker"].waitUntilGone(),
            "the picker did not close: \(app.debugDescription)"
        )
    }

    /// The set-table section whose title is `name`, scrolled into view (the table is lazy).
    @MainActor
    private func section(named name: String, in app: XCUIApplication) -> XCUIElement {
        let any = app.descendants(matching: .any)
        let title = any.matching(
            NSPredicate(format: "identifier BEGINSWITH 'settable.name.' AND label BEGINSWITH %@", name)
        )
        .firstMatch
        for _ in 0..<12 where !title.exists || !title.isHittable { app.swipeUp() }
        XCTAssertTrue(title.waitForExistence(timeout: 5), "no block named \(name)")
        let id = title.identifier.replacingOccurrences(of: "settable.name.", with: "")
        let section = any["settable.section.\(id)"].firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 5), "no section for \(name)")
        return section
    }

    @MainActor
    func testActiveWorkoutPlankHasTimeCellAndNoWeightCell() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let any = app.descendants(matching: .any)

        // Anchor: the sample workout's first block is a normal exercise with weight cells.
        XCTAssertTrue(
            fields(in: app, ending: ".weight").firstMatch.waitForExistence(timeout: 10),
            "no weight cell to anchor on"
        )

        addPlank(app, from: app.buttons["cover.addExercise"].firstMatch)

        let plank = section(named: "Plank", in: app)
        let reps = fields(in: plank, ending: ".reps")
        XCTAssertTrue(reps.firstMatch.waitForExistence(timeout: 5), "Plank has no Time cell")
        XCTAssertGreaterThan(reps.count, 0)
        XCTAssertEqual(reps.firstMatch.label, "Duration", "Plank's cell is not a duration cell")
        XCTAssertEqual(fields(in: plank, ending: ".weight").count, 0, "Plank rows show a weight cell")

        // Typing 45 into the Time cell shows 45 (seconds; `countText` renders the plain number).
        let time = reps.firstMatch
        time.tap()
        time.typeText("45")
        XCTAssertTrue(
            waitUntil { (time.value as? String) == "45" },
            "Time cell reads \(time.value as? String ?? "nil")"
        )
        app.buttons["setkeyboard.done"].firstMatch.tap()
        XCTAssertTrue(waitUntil { (time.value as? String) == "45" })
        XCTAssertTrue(any["screen.activeWorkout"].exists)
    }

    @MainActor
    func testTemplateEditorPlankHasTimeCellAndNoWeightCell() throws {
        let app = XCUIApplication.launchedForTesting(["-seedSampleData"])
        let any = app.descendants(matching: .any)

        let card = app.firstTemplateCard
        XCTAssertTrue(card.waitForExistence(timeout: 10), "no template cards")
        card.tap()
        XCTAssertTrue(any["template.preview"].waitForExistence(timeout: 5))
        let edit = app.buttons["template.edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "no Edit item in the preview")
        edit.tap()
        XCTAssertTrue(any["screen.templateEditor"].waitForExistence(timeout: 10), "Edit did not push the editor")

        // Anchor: the template's own blocks have weight cells.
        XCTAssertTrue(
            fields(in: app, ending: ".weight").firstMatch.waitForExistence(timeout: 10),
            "no weight cell to anchor on"
        )

        addPlank(app, from: app.buttons["templateEditor.addExercise"].firstMatch)

        let plank = section(named: "Plank", in: app)
        XCTAssertTrue(
            fields(in: plank, ending: ".reps").firstMatch.waitForExistence(timeout: 5),
            "Plank has no Time cell"
        )
        XCTAssertEqual(fields(in: plank, ending: ".weight").count, 0, "Plank rows show a weight cell")
    }
}
