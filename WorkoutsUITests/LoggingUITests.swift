import XCTest

/// The logging screen (task 2.4): start an empty workout from the Workout tab, add an exercise from the picker, use the
/// Previous cell and check the set.
final class LoggingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEmptyWorkoutAddExercisePreviousAndCheck() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()
        let any = app.descendants(matching: .any)

        // Sample data gives the exercises a Previous.
        let settings = app.buttons["toolbar.settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let load = app.buttons["settings.loadSampleData"].firstMatch
        // The debug row is the last section of the Settings form, below the fold on the closed Duo.
        XCTAssertTrue(any["screen.settings"].waitForExistence(timeout: 5))
        for _ in 0..<5 where !load.isHittable { app.swipeUp() }
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        load.tap()
        let ok = app.alerts.buttons["OK"].firstMatch
        XCTAssertTrue(ok.waitForExistence(timeout: 10))
        ok.tap()
        let done = app.buttons["settings.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        // Add -> Empty Workout opens the cover.
        let add = app.buttons["toolbar.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let empty = app.buttons["toolbar.add.emptyWorkout"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        empty.tap()
        XCTAssertTrue(any["screen.activeWorkout"].waitForExistence(timeout: 10))

        // Add Exercise -> search "Barbell Bench Press" (in the sample history) -> tick it -> Add.
        let addExercise = app.buttons["cover.addExercise"].firstMatch
        XCTAssertTrue(addExercise.waitForExistence(timeout: 5))
        addExercise.tap()
        XCTAssertTrue(any["screen.exercisePicker"].waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3) {
            let button = app.buttons["Search"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText("Barbell Bench Press\n")
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'picker.row.' AND label BEGINSWITH 'Barbell Bench Press'")
        )
        let row = rows.element(boundBy: 0)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let pickerAdd = any["picker.add"].firstMatch
        if !pickerAdd.exists {
            let close = app.buttons["close"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            close.tap()
        }
        XCTAssertTrue(pickerAdd.waitForExistence(timeout: 5))
        XCTAssertTrue(pickerAdd.isEnabled)
        pickerAdd.tap()

        // The exercise lands with three empty sets.
        let checks = app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.check'")
        )
        XCTAssertTrue(checks.element(boundBy: 0).waitForExistence(timeout: 10), "no set rows after Add")
        XCTAssertEqual(checks.count, 3)

        // The Previous cell fills the weight field; the check reads Done.
        let previous = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.previous'")
        )
        .element(boundBy: 0)
        XCTAssertTrue(previous.waitForExistence(timeout: 5), "no Previous cell")
        let weight = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.weight'")
        )
        .element(boundBy: 0)
        XCTAssertTrue(weight.exists)
        XCTAssertEqual(weight.value as? String, "Empty")
        previous.tap()
        expectation(for: NSPredicate(format: "value != 'Empty'"), evaluatedWith: weight)
        waitForExpectations(timeout: 5)
        XCTAssertFalse((weight.value as? String ?? "").isEmpty)

        let check = checks.element(boundBy: 0)
        XCTAssertEqual(check.value as? String, "Not done")
        check.tap()
        XCTAssertEqual(check.value as? String, "Done")
    }
}
