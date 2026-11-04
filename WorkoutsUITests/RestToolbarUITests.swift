import XCTest

/// The logging toolbar's rest controls (task 2.6): while a rest runs, Skip and +30 s sit beside the ring; +30 s lengthens the
/// rest, Skip ends it, checking a set starts it again, and Minimise returns to the Workout tab.
final class RestToolbarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// `m:ss` (or `h:mm:ss`) to seconds; nil when the text is not a time.
    private func seconds(from text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// The ring's remaining time: its label reads "Rest timer, 4:57" (the strip drops accessibility values).
    private func ringTime(_ ring: XCUIElement) -> String? {
        ring.label.components(separatedBy: ", ").dropFirst().first
    }

    @MainActor
    func testSkipPlus30CheckAndMinimise() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-startSampleWorkout", "-openWorkoutCover"]
        app.launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.activeWorkout"].waitForExistence(timeout: 15))

        let ring = app.buttons["rest.ring"].firstMatch
        let skip = app.buttons["rest.toolbar.skip"].firstMatch
        let plus30 = app.buttons["rest.toolbar.plus30"].firstMatch

        // The launch argument starts a 300 s rest: both items are there.
        XCTAssertTrue(ring.waitForExistence(timeout: 10))
        XCTAssertTrue(plus30.waitForExistence(timeout: 5), "+30 s item missing while a rest runs")
        XCTAssertTrue(skip.exists, "Skip item missing while a rest runs")

        // +30 s raises the ring's remaining time.
        let before = try XCTUnwrap(seconds(from: ringTime(ring)), "ring label \(ring.label)")
        plus30.tap()
        expectation(
            for: NSPredicate { _, _ in
                guard let now = self.seconds(from: self.ringTime(ring)) else { return false }
                return now >= before + 25
            },
            evaluatedWith: nil
        )
        waitForExpectations(timeout: 5)

        // Skip ends the rest: the items go and the ring is the idle menu again.
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5), "Skip item stayed after Skip")
        XCTAssertTrue(plus30.waitForNonExistence(timeout: 5))
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        ring.tap()
        XCTAssertTrue(app.buttons["rest.custom"].firstMatch.waitForExistence(timeout: 5), "ring is not the idle menu")
        // Close the menu by starting a preset, then skip that rest too.
        app.buttons["rest.preset.30"].firstMatch.tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))

        // Checking the first set starts a rest again.
        let check = app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.check'")
        ).element(boundBy: 0)
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        check.tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "checking a set did not start a rest")

        // Minimise lands on the Workout tab.
        app.buttons["cover.minimise"].firstMatch.tap()
        XCTAssertTrue(any["screen.workout"].waitForExistence(timeout: 10))
    }
}
