import XCTest

/// The real-store proof for the Health enrichment (PLAN 7.1b-d): seeds a Functional Strength workout into the simulator's
/// Health store, reads it back through `HealthKitSource` and checks the `FitnessCard` numbers. It drives the Health Access
/// sheet(s), so it is out of the normal suites: it skips itself unless `HEALTH_INTEGRATION` is set, which
/// `./dev ui-test HealthKitIntegrationUITests` does (via `TEST_RUNNER_HEALTH_INTEGRATION`). See docs/port/healthkit.md.
final class HealthKitIntegrationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["HEALTH_INTEGRATION"] != nil,
            "Real Health store test: run with ./dev ui-test HealthKitIntegrationUITests"
        )
    }

    @MainActor
    func testSeededWorkoutIsReadBackFromTheRealStore() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-seedHealth", "-healthReal", "-preview", "FitnessCard"]
        app.launch()

        let card = app.descendants(matching: .any)["fitness.card"].firstMatch
        let health = XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService")
        let answered = answerHealthSheets(health, until: card)

        XCTAssertTrue(
            card.waitForExistence(timeout: 20),
            "no fitness.card after \(answered) Health pages; health sheet: \(health.debugDescription)"
        )
        let label = card.label
        XCTAssertTrue(label.contains("300 active calories"), "label was \(label)")
        let average = try XCTUnwrap(averageHeartRate(in: label), "no average heart rate in \(label)")
        XCTAssertTrue((90...160).contains(average), "average heart rate \(average) in \(label)")
    }

    /// Answers up to three Health Access pages (topics, then the iOS 27 data range, for the seeder's share request and the
    /// demo's read request) until the card shows. A simulator that already granted access shows none.
    @MainActor
    @discardableResult
    private func answerHealthSheets(_ health: XCUIApplication, until card: XCUIElement) -> Int {
        var answered = 0
        let deadline = Date.now.addingTimeInterval(90)
        while answered < 3, Date.now < deadline, !card.exists {
            let allTopics = health.descendants(matching: .any)["UIA.Health.AuthSheet.AllCategoryButton"].firstMatch
            let range = health.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Past 30 Days'")).firstMatch
            if allTopics.exists {
                // Selecting all topics flips the label to "Deselect"; tapping again would clear them.
                let text = allTopics.staticTexts.firstMatch
                if text.exists, text.label.hasPrefix("Select All") {
                    text.tap()
                }
                let allow = health.buttons["UIA.Health.Allow.Button"]
                // Allow is absent from the accessibility tree until the table is scrolled.
                for _ in 0..<3 where !allow.exists {
                    health.tables.firstMatch.swipeUp()
                }
                if allow.waitForExistence(timeout: 3) {
                    allow.tap()
                    answered += 1
                }
            } else if range.exists {
                range.tap()
                let allow = health.buttons["Allow"]
                if allow.waitForExistence(timeout: 3) {
                    allow.tap()
                    answered += 1
                }
            } else {
                _ = card.waitForExistence(timeout: 1)
            }
        }
        return answered
    }

    /// The number after "average heart rate" in the card's label.
    private func averageHeartRate(in label: String) -> Double? {
        guard let range = label.range(of: #"average heart rate (\d+)"#, options: .regularExpression) else { return nil }
        return Double(label[range].filter(\.isNumber))
    }
}
