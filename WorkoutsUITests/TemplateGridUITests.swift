import XCTest

/// The template card grid on the Workout tab (task 3.2a), on the gallery entry `Workout` (sample folders and templates).
final class TemplateGridUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-preview", "Workout"]
        app.launch()
        return app
    }

    private func cards(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workout.template.'"))
    }

    @MainActor
    func testCardsShowAndOpenThePreview() throws {
        let app = launch()
        let first = cards(app).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertEqual(cards(app).count, 3, "the sample has three templates")
        XCTAssertTrue(first.label.contains("exercise"), "label should carry the exercise count: \(first.label)")
        let name = first.label.components(separatedBy: ", ").first ?? ""
        XCTAssertFalse(name.isEmpty)

        first.tap()
        let preview = app.descendants(matching: .any)["template.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "tapping a card should show the preview")
        XCTAssertTrue(app.staticTexts[name].firstMatch.exists, "the preview should be titled \(name)")

        app.buttons["template.preview.close"].firstMatch.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: preview)
        wait(for: [gone], timeout: 5)
        XCTAssertTrue(first.exists)
    }
}
