import XCTest

/// The Health fixture path: `-healthFixture` feeds `HealthEnrichment`, and the `FitnessCard` gallery entry renders the result.
final class FitnessFixtureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-preview", "FitnessCard", "-healthFixture", fixture]
        app.launch()
        return app
    }

    @MainActor
    func testFullFixtureShowsCard() throws {
        let app = launch(fixture: "full")
        let card = app.descendants(matching: .any)["fitness.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("118"), "label was \(card.label)")
        XCTAssertTrue(card.label.contains("310"), "label was \(card.label)")
        XCTAssertTrue(card.label.contains("effort 8"), "label was \(card.label)")
        XCTAssertTrue(card.label.contains("5 zones"), "label was \(card.label)")
    }

    @MainActor
    func testDeniedFixtureShowsHealthAccessOff() throws {
        let app = launch(fixture: "denied")
        XCTAssertTrue(app.staticTexts["Health access off"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["fitness.card"].exists)
    }
}
