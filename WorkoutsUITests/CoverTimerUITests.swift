import XCTest

/// The logging screen's navigation subtitle ("Nov 8 · 0:52") keeps counting while the user does nothing.
final class CoverTimerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSubtitleElapsedTimeTicksWithoutInteraction() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let subtitle = app.navigationBars.staticTexts
            .matching(NSPredicate(format: "label MATCHES %@", ".*· \\d+:\\d\\d.*")).firstMatch
        XCTAssertTrue(subtitle.waitForExistence(timeout: 10), "navigation subtitle missing")

        let before = subtitle.label
        Thread.sleep(forTimeInterval: 2.5)
        let after = subtitle.label
        XCTAssertNotEqual(before, after, "elapsed time did not tick without interaction")
    }
}
