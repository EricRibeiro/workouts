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

    /// A tab's own sheet (History's Calendar) is up when the link arrives: the sheet closes and the cover opens, instead of
    /// leaving neither the cover nor the resume ring.
    @MainActor
    func testWorkoutLinkClosesATabSheetAndOpensTheCover() throws {
        let app = XCUIApplication.launchedForTesting(["-startSampleWorkout"], waitingFor: "screen.workout", timeout: 15)
        let any = app.descendants(matching: .any)
        XCTAssertTrue(app.buttons["resume.ring"].firstMatch.waitForExistence(timeout: 10), "no minimised workout")
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 10))
        app.buttons["history.calendar"].tap()
        XCTAssertTrue(any["screen.calendar"].waitForExistence(timeout: 5), "the calendar sheet did not open")

        try openLink("workouts://workout")
        let cover = any["screen.activeWorkout"].waitForExistence(timeout: 10)
        // Whatever happens to the cover, the person is never left with neither it nor the ring.
        XCTAssertTrue(cover || app.buttons["resume.ring"].firstMatch.exists, "neither the cover nor the resume ring")
        XCTAssertTrue(cover, "workouts://workout did not open the cover over the calendar sheet")
        XCTAssertFalse(any["screen.calendar"].exists, "the calendar sheet stayed up")
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
