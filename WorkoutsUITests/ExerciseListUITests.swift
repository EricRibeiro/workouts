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
        let app = XCUIApplication.launchedPreview("Exercises", waitingFor: "screen.exercises")

        let any = app.descendants(matching: .any)

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
        XCTAssertTrue(any["screen.exerciseDetail"].waitForExistence(timeout: 5), "tapping a row did not open a detail")
    }

    /// Dragging the list down at its top and releasing opens search (once the list is at rest) and brings up the keyboard.
    @MainActor
    func testPullDownOpensSearch() throws {
        let app = XCUIApplication.launchedPreview("Exercises", waitingFor: "screen.exercises")
        let rows = rows(app)
        let row = rows.element(boundBy: 0)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no exercise rows")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "keyboard was up before the pull")

        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 260)))

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "pulling down did not open search")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.exists)
        search.typeText("bench\n")

        let first = rows.element(boundBy: 0)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.localizedCaseInsensitiveContains("bench"), "first row was \(first.label)")
    }

    /// By default every name is one line, cut at the tail, so rows next to each other match whether or not the name is long.
    @MainActor
    func testRowsHaveEqualHeightByDefault() throws {
        let app = XCUIApplication.launchedPreview("Exercises", waitingFor: "screen.exercises")
        let rows = rows(app)
        XCTAssertTrue(rows.element(boundBy: 1).waitForExistence(timeout: 10), "fewer than two exercise rows")
        let first = rows.element(boundBy: 0).frame
        let second = rows.element(boundBy: 1).frame
        XCTAssertGreaterThan(first.height, 0)
        XCTAssertEqual(first.height, second.height, accuracy: 1, "first rows differ in height")
    }

    /// With "Full Exercise Names" on, names wrap to two lines and every row takes the two-line height, so rows still
    /// match, and each is taller than a default one-line row.
    @MainActor
    func testRowsHaveEqualTwoLineHeightWithFullExerciseNames() throws {
        let defaultApp = XCUIApplication.launchedPreview("Exercises", waitingFor: "screen.exercises")
        let defaultRows = rows(defaultApp)
        XCTAssertTrue(defaultRows.element(boundBy: 1).waitForExistence(timeout: 10), "fewer than two exercise rows")
        let oneLineHeight = defaultRows.element(boundBy: 0).frame.height
        defaultApp.terminate()

        let app = XCUIApplication.launchedPreview(
            "Exercises",
            extraArguments: ["-fullExerciseNames", "YES"],
            waitingFor: "screen.exercises"
        )
        let rows = rows(app)
        XCTAssertTrue(rows.element(boundBy: 1).waitForExistence(timeout: 10), "fewer than two exercise rows")
        let first = rows.element(boundBy: 0).frame
        let second = rows.element(boundBy: 1).frame
        XCTAssertEqual(first.height, second.height, accuracy: 1, "first rows differ in height")
        XCTAssertGreaterThan(first.height, oneLineHeight, "full names did not reserve the two-line height")
    }

    @MainActor
    func testBodyPartFilterAndShowRetired() throws {
        let app = XCUIApplication.launchedPreview("Exercises")

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

        // Show Retired keeps one spoken label; the toggle state is its selected trait (the toolbar may fold it into the overflow
        // on the closed Duo).
        let toggle = app.descendants(matching: .any).matching(identifier: "exercises.showRetired").firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "Show Retired Exercises")
        XCTAssertFalse(toggle.isSelected, toggle.debugDescription)
        toggle.tap()
        let after = app.descendants(matching: .any).matching(identifier: "exercises.showRetired").firstMatch
        XCTAssertEqual(after.label, "Show Retired Exercises")
        XCTAssertTrue(after.isSelected, after.debugDescription)
    }

    /// R4-02: the best-set column follows the display unit chosen in Settings (the default unit is lb).
    @MainActor
    func testBestSetFollowsUnitChange() throws {
        let app = XCUIApplication.launchedForTesting()
        let any = app.descendants(matching: .any)

        // Sample data gives the exercises a best set.
        let settings = any["toolbar.settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let load = app.buttons["settings.loadSampleData"].firstMatch
        XCTAssertTrue(any["screen.settings"].waitForExistence(timeout: 5))
        for _ in 0..<5 where !load.isHittable { app.swipeUp() }
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        load.tap()
        let ok = app.alerts.buttons["OK"].firstMatch
        XCTAssertTrue(ok.waitForExistence(timeout: 10))
        ok.tap()
        app.buttons["settings.done"].firstMatch.tap()

        any["tab.exercises"].firstMatch.tap()
        XCTAssertTrue(any["screen.exercises"].waitForExistence(timeout: 5))
        let withBest = rows(app).matching(NSPredicate(format: "label CONTAINS ' lb ×'"))
        let row = withBest.element(boundBy: 0)
        // Alphabetical, so the exercises with history sit below the fold.
        for _ in 0..<15 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no row shows a best set in lb")
        let identifier = row.identifier

        // Switch to kg in Settings and come back: the same row now reads in kg.
        any["tab.workout"].firstMatch.tap()
        settings.tap()
        let unit = app.segmentedControls["settings.defaultUnit"]
        XCTAssertTrue(unit.waitForExistence(timeout: 5), "no unit control")
        unit.buttons["kg"].tap()
        XCTAssertTrue(unit.buttons["kg"].isSelected)
        app.buttons["settings.done"].firstMatch.tap()

        any["tab.exercises"].firstMatch.tap()
        let same = rows(app).matching(identifier: identifier).firstMatch
        XCTAssertTrue(same.waitForExistence(timeout: 10))
        let converted = NSPredicate(format: "label CONTAINS ' kg ×' AND NOT (label CONTAINS ' lb ×')")
        expectation(for: converted, evaluatedWith: same)
        waitForExpectations(timeout: 10)
    }
}
