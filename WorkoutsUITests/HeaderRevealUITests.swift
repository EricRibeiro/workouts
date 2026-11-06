import XCTest

/// The logging screen's title header (title menu plus "date · elapsed") minimises while the set table scrolls down and
/// comes back about 1.5 s after scrolling stops, even though the table stays scrolled.
final class HeaderRevealUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The title-menu button in the logging screen's navigation bar (the Workout tab's bar sits behind the cover).
    @MainActor
    private func titleButton(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars.matching(NSPredicate(format: "identifier != 'Workout'")).buttons.firstMatch
    }

    /// Polls until the title is present (or gone), returning the seconds it took, or nil on timeout.
    @MainActor
    private func waitForTitle(_ title: XCUIElement, present: Bool, timeout: TimeInterval) -> TimeInterval? {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if title.exists == present { return Date().timeIntervalSince(start) }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    @MainActor
    func testHeaderReturnsByItselfAfterScrolling() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let title = titleButton(app)
        XCTAssertTrue(title.waitForExistence(timeout: 10), "title menu button missing")

        // Scroll the table down and leave it there.
        let table = app.descendants(matching: .any)["settable"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        for _ in 0..<2 { table.swipeUp(velocity: .slow) }
        XCTAssertNotNil(waitForTitle(title, present: false, timeout: 3), "header did not hide while scrolling down")

        // Without touching the table again, the header comes back by itself, not right away.
        let returned = waitForTitle(title, present: true, timeout: 5)
        XCTAssertNotNil(returned, "header did not come back after scrolling stopped")
        XCTAssertTrue(app.buttons["cover.finish"].isHittable, "the cover should still be showing the scrolled table")

        // A further scroll hides it again, and it comes back again.
        table.swipeUp(velocity: .slow)
        XCTAssertNotNil(waitForTitle(title, present: false, timeout: 3), "header did not hide on the second scroll")
        XCTAssertNotNil(waitForTitle(title, present: true, timeout: 5), "header did not come back the second time")
    }
}
