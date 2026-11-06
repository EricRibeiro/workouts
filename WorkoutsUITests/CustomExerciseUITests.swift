import XCTest

/// The custom exercise form (task 4.4): create and delete from the Exercises tab, and inline create from the picker.
final class CustomExerciseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Types `text` into the search field, tapping the folded search button first when the field is not out yet.
    @MainActor
    private func search(_ app: XCUIApplication, _ text: String) {
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 3) {
            let button = app.buttons["Search"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "search field did not take focus")
        }
        field.typeText(text)
    }

    @MainActor
    func testCreateThenDeleteUnusedExercise() throws {
        let app = XCUIApplication.launchedPreview("Exercises", waitingFor: "screen.exercises")
        let any = app.descendants(matching: .any)

        // New Exercise: Save is disabled until the name is valid.
        let new = any["exercises.new"].firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.tap()
        XCTAssertTrue(any["screen.newExercise"].waitForExistence(timeout: 5))
        let save = any["customExercise.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        let name = app.textFields["customExercise.name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Zz Test Curl")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertFalse(any["screen.newExercise"].waitForExistence(timeout: 2))

        // The row appears with the Custom tag (search narrows the long list to it).
        search(app, "Zz Test Curl\n")
        let row = any.matching(
            NSPredicate(format: "identifier BEGINSWITH 'exercises.row.' AND label BEGINSWITH 'Zz Test Curl'")
        )
        .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the new exercise is not in the list")
        XCTAssertTrue(row.label.contains("Custom"), "row was \(row.label)")

        // Open it, Edit, Delete (nothing references it), confirm.
        row.tap()
        XCTAssertTrue(any["screen.exerciseDetail"].waitForExistence(timeout: 5))
        let edit = any["exerciseDetail.edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(any["screen.editExercise"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["customExercise.name"].firstMatch.value as? String, "Zz Test Curl")
        XCTAssertFalse(any["customExercise.archive"].exists, "an unused exercise offers Delete, not Archive")
        let delete = any["customExercise.delete"].firstMatch
        // The Form is about three pages tall on the closed display and its rows are lazy, so one swipe may stop short of the
        // Delete row; swipe until it exists (bounded) rather than assuming a single swipe reaches the end.
        var swipes = 0
        while !delete.waitForExistence(timeout: 2) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no confirmation dialog")
        confirm.tap()
        XCTAssertFalse(any["screen.editExercise"].waitForExistence(timeout: 2))

        // Gone from the list.
        XCTAssertTrue(any["screen.exercises"].waitForExistence(timeout: 5))
        XCTAssertFalse(row.waitForExistence(timeout: 2), "the deleted exercise is still listed")
    }

    /// Editing a custom exercise's weight type refreshes its open detail: the chart offers the new type's metrics and
    /// selects one of them, instead of keeping the old type's metric with no chip selected.
    @MainActor
    func testChangingWeightTypeUpdatesTheChartMetrics() throws {
        let app = XCUIApplication.launchedPreview("Exercises", waitingFor: "screen.exercises")
        let any = app.descendants(matching: .any)

        any["exercises.new"].firstMatch.tap()
        let name = app.textFields["customExercise.name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Zz Type Curl")
        any["customExercise.save"].firstMatch.tap()
        XCTAssertFalse(any["screen.newExercise"].waitForExistence(timeout: 2))

        search(app, "Zz Type Curl\n")
        let row = any.matching(
            NSPredicate(format: "identifier BEGINSWITH 'exercises.row.' AND label BEGINSWITH 'Zz Type Curl'")
        )
        .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let segment = app.segmentedControls["exerciseDetail.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 5))
        segment.buttons["Charts"].tap()
        let est1RM = app.buttons["exerciseDetail.chart.metric.e1rm"].firstMatch
        XCTAssertTrue(est1RM.waitForExistence(timeout: 5))
        XCTAssertTrue(est1RM.isSelected, "Weight and reps starts on Est. 1RM")

        let edit = any["exerciseDetail.edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(any["screen.editExercise"].waitForExistence(timeout: 5))
        let weightType = any["customExercise.weightType"].firstMatch
        XCTAssertTrue(weightType.waitForExistence(timeout: 5))
        weightType.tap()
        let assisted = app.buttons["Assisted bodyweight (less is better)"].firstMatch
        XCTAssertTrue(assisted.waitForExistence(timeout: 5))
        assisted.tap()
        any["customExercise.save"].firstMatch.tap()
        XCTAssertFalse(any["screen.editExercise"].waitForExistence(timeout: 2))

        let leastAssistance = app.buttons["exerciseDetail.chart.metric.maxWeight"].firstMatch
        XCTAssertTrue(leastAssistance.waitForExistence(timeout: 5))
        XCTAssertFalse(est1RM.exists, "Est. 1RM is not offered for an assisted exercise")
        XCTAssertTrue(leastAssistance.isSelected, "the chart did not move to a metric the new type offers")
    }

    @MainActor
    func testPickerCreateTicksTheNewExercise() throws {
        let app = XCUIApplication.launchedPreview("ExercisePickerMulti", waitingFor: "screen.exercisePicker")
        let any = app.descendants(matching: .any)

        search(app, "Zz Nonexistent\n")
        let create = any["picker.createCustom"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5), "no Create row for an empty search")
        create.tap()

        // The form opens with the search text as the name.
        XCTAssertTrue(any["screen.newExercise"].waitForExistence(timeout: 5))
        let name = app.textFields["customExercise.name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Zz Nonexistent")
        let save = any["customExercise.save"].firstMatch
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertFalse(any["screen.newExercise"].waitForExistence(timeout: 2))

        // The new exercise is in the results and ticked (the New row stays: it is always available).
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'picker.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the new exercise is not in the results")
        XCTAssertTrue(row.label.contains("Zz Nonexistent"), "row was \(row.label)")
        XCTAssertTrue(row.isSelected, "the new exercise is not ticked")
    }

    @MainActor
    func testPickerNewIsReachableWithResultsAndTicksTheNewExercise() throws {
        let app = XCUIApplication.launchedPreview("ExercisePickerMulti", waitingFor: "screen.exercisePicker")
        let any = app.descendants(matching: .any)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'picker.row.'"))

        // With the full list showing (no search), New is there.
        let create = any["picker.createCustom"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5), "no New control with results showing")
        XCTAssertTrue(rows.firstMatch.exists)

        // And while a search has results, prefilled with the search text.
        search(app, "squat\n")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(create.waitForExistence(timeout: 5), "no New control while a search has results")
        create.tap()

        XCTAssertTrue(any["screen.newExercise"].waitForExistence(timeout: 5))
        let name = app.textFields["customExercise.name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "squat")
        name.tap()
        // Rename so the new exercise sorts first and is rendered by the lazy list among the many squat results.
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "Aaa Squat Zz")
        any["customExercise.save"].firstMatch.tap()
        XCTAssertFalse(any["screen.newExercise"].waitForExistence(timeout: 2))

        let created = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'picker.row.' AND label CONTAINS 'Aaa Squat Zz'")
        )
        .firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 5), "the new exercise is not in the results")
        XCTAssertTrue(created.isSelected, "the new exercise is not ticked")
    }
}
