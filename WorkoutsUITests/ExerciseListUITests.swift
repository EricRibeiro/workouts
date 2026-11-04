import XCTest

/// The Exercises list on the gallery entry `Exercises` (task 4.1a): rows, search, and opening a row.
final class ExerciseListUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'exercises.row.'")
        )
    }

    @MainActor
    func testListSearchAndOpen() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-preview", "Exercises"]
        app.launch()

        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.exercises"].waitForExistence(timeout: 10))

        let rows = rows(app)
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 10), "no exercise rows")
        let initialFirst = rows.element(boundBy: 0).label
        XCTAssertFalse(initialFirst.isEmpty)

        // On the closed Duo the system folds search into a button in the trailing strip; tap it to get the field.
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3) {
            let button = app.buttons["Search"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText("bench\n")

        let first = rows.element(boundBy: 0)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("Bench"), "first row was \(first.label)")
        let count = rows.count
        XCTAssertGreaterThan(count, 0)
        for index in 0..<min(count, 6) {
            XCTAssertTrue(
                rows.element(boundBy: index).label.localizedCaseInsensitiveContains("bench"),
                "row \(index) was \(rows.element(boundBy: index).label)"
            )
        }

        // Exercises with history carry their best set in the label ("name, tags, 100 kg × 5").
        let withBest = rows.matching(NSPredicate(format: "label CONTAINS '×'"))
        XCTAssertGreaterThan(withBest.count, 0, "no row shows a best set")

        // Opening a row shows its detail: beside the list on regular width, pushed on compact.
        first.tap()
        XCTAssertTrue(any["exercises.detail"].waitForExistence(timeout: 5), "tapping a row did not open a detail")
    }
}
