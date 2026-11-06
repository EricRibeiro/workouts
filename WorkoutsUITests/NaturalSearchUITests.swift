import XCTest

/// Natural-language search (task 4.6) on the Exercises gallery entry with the stubbed parser (`-stubQueryParser`): a
/// sentence with no plain match shows the stub's matches, a plain match never reaches the parser.
final class NaturalSearchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'exercises.row.'")
        )
    }

    /// Opens the search field (on the closed Duo the system folds it into a button) and types `text`.
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
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.launchedPreview(
            "Exercises",
            extraArguments: ["-stubQueryParser"],
            waitingFor: "screen.exercises"
        )
        XCTAssertTrue(rows(app).element(boundBy: 0).waitForExistence(timeout: 10), "no exercise rows")
        return app
    }

    @MainActor
    func testSentenceWithNoPlainMatchShowsStubbedMatches() throws {
        let app = launch()
        search(app, "chest with dumbbells")

        // Debounce (400 ms) plus the stub: the rows become Chest exercises that use dumbbells.
        let rows = rows(app)
        let first = rows.element(boundBy: 0)
        let predicate = NSPredicate(format: "label CONTAINS[c] 'Dumbbell'")
        expectation(for: predicate, evaluatedWith: first)
        waitForExpectations(timeout: 10)
        let count = rows.count
        XCTAssertGreaterThan(count, 0)
        for index in 0..<min(count, 6) {
            let label = rows.element(boundBy: index).label
            XCTAssertTrue(label.localizedCaseInsensitiveContains("Chest"), "row \(index) was \(label)")
            XCTAssertTrue(label.localizedCaseInsensitiveContains("Dumbbell"), "row \(index) was \(label)")
        }
    }

    @MainActor
    func testPlainMatchStillUsesPlainSearch() throws {
        let app = launch()
        search(app, "bench")

        // The stub answers "legs" for anything but a chest sentence, so a leaked parse would show Legs rows.
        let rows = rows(app)
        let first = rows.element(boundBy: 0)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        // Nothing on screen marks a parse in flight, so watch for the leak itself for a bit past the debounce (400 ms): it
        // fails the moment a non-"bench" row appears and otherwise passes once the window closes.
        let leaked = waitUntil(timeout: 1) {
            (0..<min(rows.count, 6)).contains {
                !rows.element(boundBy: $0).label.localizedCaseInsensitiveContains("bench")
            }
        }
        XCTAssertFalse(leaked, "a plain match was replaced by parsed results")
        let count = rows.count
        XCTAssertGreaterThan(count, 0)
        for index in 0..<min(count, 6) {
            let label = rows.element(boundBy: index).label
            XCTAssertTrue(label.localizedCaseInsensitiveContains("bench"), "row \(index) was \(label)")
        }
    }
}
