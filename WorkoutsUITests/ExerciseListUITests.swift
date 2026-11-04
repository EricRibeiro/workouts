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
        // The field animates in and takes focus a beat after it exists; tap it only if the keyboard is not up yet.
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            search.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "search field did not take focus")
        }
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

    @MainActor
    func testBodyPartFilterAndShowRetired() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-preview", "Exercises"]
        app.launch()

        let rows = rows(app)
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 10), "no exercise rows")
        let unfiltered = rows.count

        let bodyPart = app.buttons.matching(identifier: "exercises.filter.bodyPart").firstMatch
        XCTAssertTrue(bodyPart.waitForExistence(timeout: 5))
        XCTAssertEqual(bodyPart.label, "Body Part: Any Body Part")
        bodyPart.tap()
        // The menu's picker rows surface as buttons in the popover's collection view (the last one on screen); pick
        // the second row (the menu lists "Any Body Part" first).
        XCTAssertTrue(app.buttons["Any Body Part"].waitForExistence(timeout: 5), "the filter menu did not open")
        let menu = app.collectionViews.containing(
            NSPredicate(
                format: "elementType == %d AND label == 'Any Body Part'",
                XCUIElement.ElementType.button.rawValue
            )
        ).firstMatch
        let item = menu.cells.element(boundBy: 1).buttons.firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the menu has no second item")
        let chosen = item.label
        XCTAssertNotEqual(chosen, "Any Body Part")
        item.tap()

        XCTAssertEqual(bodyPart.label, "Body Part: \(chosen)")
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 5))
        let filtered = min(rows.count, 8)
        XCTAssertGreaterThan(filtered, 0)
        for index in 0..<filtered {
            let label = rows.element(boundBy: index).label
            XCTAssertTrue(label.contains(chosen), "row \(index) '\(label)' lacks '\(chosen)'")
        }

        // Back to Any: the list is whole again.
        bodyPart.tap()
        let any = app.buttons["Any Body Part"]
        XCTAssertTrue(any.waitForExistence(timeout: 5))
        any.tap()
        XCTAssertEqual(bodyPart.label, "Body Part: Any Body Part")
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(rows.count, unfiltered)

        // Show Retired toggles its label (the toolbar may fold it into the overflow on the closed Duo).
        let toggle = app.descendants(matching: .any).matching(identifier: "exercises.showRetired").firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "Show Retired")
        toggle.tap()
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "exercises.showRetired").firstMatch.label,
            "Hide Retired"
        )
    }
}
