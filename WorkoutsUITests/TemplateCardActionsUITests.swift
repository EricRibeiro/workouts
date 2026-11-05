import XCTest

/// The template cards' context menu and New Template (task 3.2b): long-press a card for Edit, Duplicate, Move and Delete,
/// and the Add menu's New Template pushes the editor. These use the real app with the sample data (`-seedSampleData`).
final class TemplateCardActionsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.launchedForTesting(["-seedSampleData"])
        return app
    }

    private func cards(_ app: XCUIApplication, named name: String) -> XCUIElementQuery {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'workout.template.' AND label BEGINSWITH %@", name)
        )
    }

    private func name(of card: XCUIElement) -> String {
        card.label.components(separatedBy: ", ").first ?? ""
    }

    @MainActor
    func testDuplicateAddsACopyNextToTheOriginal() throws {
        let app = launch()
        let card = app.firstTemplateCard
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let original = name(of: card)
        XCTAssertFalse(original.isEmpty)

        card.press(forDuration: 1.0)
        let duplicate = app.buttons["templateCard.duplicate"].firstMatch
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5), "the long press should open the card menu")
        XCTAssertTrue(app.buttons["templateCard.edit"].firstMatch.exists)
        XCTAssertTrue(app.buttons["templateCard.delete"].firstMatch.exists)
        duplicate.tap()

        XCTAssertTrue(
            cards(app, named: "\(original) copy").firstMatch.waitForExistence(timeout: 5),
            "a card named \"\(original) copy\" should appear"
        )
    }

    @MainActor
    func testDeleteAsksThenRemovesTheCard() throws {
        let app = launch()
        let card = app.firstTemplateCard
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let doomed = name(of: card)
        let before = cards(app, named: doomed).count

        card.press(forDuration: 1.0)
        let delete = app.buttons["templateCard.delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        let confirm = app.buttons["templateCard.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete should ask first")
        XCTAssertEqual(cards(app, named: doomed).count, before, "nothing is deleted before the confirmation")
        confirm.tap()

        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        let gone = NSPredicate(format: "count == %d", before - 1)
        expectation(for: gone, evaluatedWith: cards(app, named: doomed))
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testNewTemplateInTheAddMenuOpensTheEditor() throws {
        let app = launch()
        let add = app.buttons["toolbar.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let newTemplate = app.buttons["workout.newTemplate"].firstMatch
        XCTAssertTrue(newTemplate.waitForExistence(timeout: 5))
        XCTAssertEqual(newTemplate.label, "New Template")
        newTemplate.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["screen.templateEditor"].waitForExistence(timeout: 5),
            "New Template should push the editor"
        )
    }
}
