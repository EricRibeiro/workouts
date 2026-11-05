import XCTest

/// The resume control (task 2.7): Minimise leaves a ring in the toolbar of every tab; tapping it brings the logging cover back.
final class ResumeControlUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRingOnEveryTabRestoresTheCover() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let any = app.descendants(matching: .any)
        let ring = app.buttons["resume.ring"].firstMatch
        XCTAssertFalse(ring.exists, "the ring shows while the cover is open")

        app.buttons["cover.minimise"].firstMatch.tap()
        XCTAssertTrue(any["screen.workout"].waitForExistence(timeout: 10))
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "no resume ring on the Workout tab")
        XCTAssertTrue(ring.label.hasPrefix("Resume workout, "), "label \(ring.label)")

        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 10))
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "no resume ring on the History tab")

        app.selectTab("tab.exercises", label: "Exercises")
        XCTAssertTrue(any["screen.exercises"].waitForExistence(timeout: 10))
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "no resume ring on the Exercises tab")

        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        ring.tap()
        XCTAssertTrue(any["screen.activeWorkout"].waitForExistence(timeout: 10), "the ring did not restore the cover")
        XCTAssertTrue(ring.waitForNonExistence(timeout: 5), "the ring stayed under the open cover")
    }
}
