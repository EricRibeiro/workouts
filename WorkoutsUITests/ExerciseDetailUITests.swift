import XCTest

/// The exercise detail (task 4.2): opened from the Exercises list, About and Records segments.
final class ExerciseDetailUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOpenSwitchToRecords() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-preview", "Exercises"]
        app.launch()

        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.exercises"].waitForExistence(timeout: 10))
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'exercises.row.'")
        )
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 10), "no exercise rows")

        // On the closed Duo the system folds search into a button in the trailing strip; tap it to get the field.
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3) {
            let button = app.buttons["Search"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            search.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "search field did not take focus")
        }
        search.typeText("Barbell Bench Press\n")

        let row = rows.matching(NSPredicate(format: "label BEGINSWITH 'Barbell Bench Press'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no Barbell Bench Press row")
        row.tap()

        XCTAssertTrue(any["screen.exerciseDetail"].waitForExistence(timeout: 5), "the detail did not open")
        let name = any["exerciseDetail.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.label, "Barbell Bench Press")

        // Library exercises have no Edit item.
        XCTAssertFalse(any["exerciseDetail.edit"].exists)

        let segment = app.segmentedControls["exerciseDetail.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 5))
        XCTAssertTrue(segment.buttons["About"].exists)
        segment.buttons["Records"].tap()

        // The sample history has Barbell Bench Press sessions, so at least the e1RM record exists.
        let e1rm = any["exerciseDetail.records.e1rm"]
        XCTAssertTrue(e1rm.waitForExistence(timeout: 5), "no Estimated 1RM record row")
        XCTAssertTrue(e1rm.label.hasPrefix("Estimated 1RM"), "label was \(e1rm.label)")
        XCTAssertTrue(any["exerciseDetail.records.heaviest"].exists)
        XCTAssertTrue(any["exerciseDetail.records.repsAtWeight.0"].exists)

        // History (task 4.3): at least one session, newest first.
        segment.buttons["History"].tap()
        let sessionCards = any.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'exerciseDetail.history.session.' AND NOT identifier CONTAINS '.set.'"
            )
        )
        XCTAssertTrue(sessionCards.firstMatch.waitForExistence(timeout: 5), "no History session")

        // Charts: the chart shows, and switching the metric keeps it.
        segment.buttons["Charts"].tap()
        XCTAssertTrue(any["exerciseDetail.chart.metric"].waitForExistence(timeout: 5))
        XCTAssertTrue(any["exerciseDetail.chart"].waitForExistence(timeout: 5), "no chart")
        let totalReps = app.buttons["exerciseDetail.chart.metric.totalReps"]
        XCTAssertTrue(totalReps.waitForExistence(timeout: 5))
        totalReps.tap()
        XCTAssertTrue(any["exerciseDetail.chart"].waitForExistence(timeout: 5), "chart gone after switching metric")
        app.buttons["exerciseDetail.chart.metric.volume"].tap()
        XCTAssertTrue(any["exerciseDetail.chart"].waitForExistence(timeout: 5), "chart gone after switching metric")

        segment.buttons["About"].tap()
        XCTAssertTrue(any["exerciseDetail.about.instructions"].waitForExistence(timeout: 5))
    }
}
