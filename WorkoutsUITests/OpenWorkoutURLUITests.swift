import XCTest

/// The Live Activity's `workouts://workout` link (banner and Dynamic Island) brings the minimised workout's cover back.
/// The app launches with the sample workout running and no cover (no `-openWorkoutCover`), so only the link can open it,
/// and the URL is delivered by the system, like a tap on the activity (`XCUIApplication.open` relaunches the app).
final class OpenWorkoutURLUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Opens `string` through the system, tapping through its "Open in Workouts?" confirmation when it appears.
    @MainActor
    private func openLink(_ string: String) throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: string)))
        let confirm = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Open"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
    }

    @MainActor
    func testWorkoutLinkReopensTheMinimisedCover() throws {
        let app = XCUIApplication.launchedForTesting(["-startSampleWorkout"], waitingFor: "screen.workout", timeout: 15)
        let any = app.descendants(matching: .any)
        XCTAssertTrue(app.buttons["resume.ring"].firstMatch.waitForExistence(timeout: 10), "no minimised workout")
        XCTAssertFalse(any["screen.activeWorkout"].exists)

        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 10))

        try openLink("workouts://workout")
        XCTAssertTrue(
            any["screen.activeWorkout"].waitForExistence(timeout: 10),
            "workouts://workout did not open the cover"
        )
    }

    @MainActor
    func testUnknownLinkIsIgnored() throws {
        let app = XCUIApplication.launchedForTesting(["-startSampleWorkout"], waitingFor: "screen.workout", timeout: 15)
        let any = app.descendants(matching: .any)
        XCTAssertTrue(app.buttons["resume.ring"].firstMatch.waitForExistence(timeout: 10), "no minimised workout")
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 10))

        try openLink("workouts://nowhere")
        XCTAssertFalse(any["screen.activeWorkout"].waitForExistence(timeout: 3), "an unknown link opened the cover")
        XCTAssertTrue(any["screen.history"].exists, "the app left the History tab")
    }
}
