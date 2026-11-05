import XCTest

extension XCUIApplication {
    /// Every template card on the Workout tab.
    var templateCards: XCUIElementQuery {
        buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workout.template.'"))
    }

    var firstTemplateCard: XCUIElement { templateCards.firstMatch }

    /// Selects a tab by identifier or label. The closed Duo's trailing strip drops the tab identifiers; the buttons keep
    /// their labels.
    @MainActor
    func selectTab(_ id: String, label: String, timeout: TimeInterval = 10) {
        let tab = buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", id, label)).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: timeout), "\(id) missing")
        tab.tap()
    }
}
