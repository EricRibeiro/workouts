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
        XCTAssertTrue(any["screen.activeWorkout"].waitForExistence(timeout: 10), "the cover is not open")
        ring.assertStaysAbsent(for: 1, "the ring shows while the cover is open")

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

    /// A rest that ends while the workout is minimised: the ring says "rest over" (not "0:00") through the grace, then
    /// falls back to the elapsed time.
    @MainActor
    func testRingSaysRestOverThenElapsed() throws {
        let app = XCUIApplication.launchedInActiveWorkout(["-sampleRestSeconds", "8"])
        let ring = app.buttons["resume.ring"].firstMatch
        app.buttons["cover.minimise"].firstMatch.tap()
        XCTAssertTrue(ring.waitForExistence(timeout: 10))
        XCTAssertTrue(ring.label.contains("rest "), "label \(ring.label)")

        let over = NSPredicate(format: "label CONTAINS 'rest over'")
        expectation(for: over, evaluatedWith: ring)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(ring.label.contains("0:00"), "label \(ring.label)")

        // 3 s grace, then the engine forgets the rest and the label reads the elapsed time.
        let elapsed = NSPredicate(format: "label ENDSWITH 'elapsed'")
        expectation(for: elapsed, evaluatedWith: ring)
        waitForExpectations(timeout: 12)
        XCTAssertTrue(ring.label.hasPrefix("Resume workout, "), "label \(ring.label)")
    }
}
