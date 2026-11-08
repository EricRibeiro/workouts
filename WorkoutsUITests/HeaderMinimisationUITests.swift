import XCTest

/// The logging screen's title header minimises while the set table scrolls down and stays minimised while the table sits
/// scrolled, even though the navigation subtitle is re-resolved every second; the system restores it on scroll up.
final class HeaderMinimisationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The title-menu button in the logging screen's navigation bar (the Workout tab's bar sits behind the cover).
    @MainActor
    private func titleButton(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars.matching(NSPredicate(format: "identifier != 'Workout'")).buttons.firstMatch
    }

    @MainActor
    func testHeaderStaysMinimisedWhileScrolledDespiteTheTickingSubtitle() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let title = titleButton(app)
        XCTAssertTrue(title.waitForExistence(timeout: 10), "title menu button missing")

        let table = app.descendants(matching: .any)["settable"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        for _ in 0..<2 { table.swipeUp(velocity: .slow) }
        XCTAssertTrue(waitUntil(timeout: 3) { !title.exists }, "header did not hide while scrolling down")

        // Five subtitle ticks pass with the table untouched: the title must not come back or flicker.
        var reappearances = 0
        var wasPresent = false
        let start = Date()
        var firstSeenAt: TimeInterval?
        while Date().timeIntervalSince(start) < 5 {
            let present = title.exists
            if present && !wasPresent {
                reappearances += 1
                firstSeenAt = firstSeenAt ?? Date().timeIntervalSince(start)
            }
            wasPresent = present
            _ = waitUntil(timeout: 0.1) { false }
        }
        XCTAssertEqual(
            reappearances,
            0,
            "header reappeared \(reappearances) time(s) while scrolled, first at \(firstSeenAt ?? -1) s"
        )

        table.swipeDown(velocity: .slow)
        XCTAssertTrue(waitUntil(timeout: 3) { title.exists }, "the system did not restore the header on scroll up")
    }
}
