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
        let app = XCUIApplication.launchedInActiveWorkout(["-sampleNoRest"])
        let ring = app.buttons["resume.ring"].firstMatch
        // Start a rest from the cover's ring, then minimise.
        let restRing = app.buttons["rest.ring"].firstMatch
        XCTAssertTrue(restRing.waitForExistence(timeout: 10), "no rest ring")
        restRing.tap()
        let preset = app.buttons["rest.preset.60"].firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        preset.tap()
        app.buttons["cover.minimise"].firstMatch.tap()
        XCTAssertTrue(ring.waitForExistence(timeout: 10))
        // Running: "Resume workout, rest m:ss" (not "rest over", which also contains "rest ").
        let running = NSPredicate(format: "label MATCHES '.*rest [0-9]+:[0-9]{2}.*'")
        expectation(for: running, evaluatedWith: ring)
        waitForExpectations(timeout: 10)

        app.expireRestNow()
        let over = NSPredicate(format: "label CONTAINS 'rest over'")
        expectation(for: over, evaluatedWith: ring)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(ring.label.contains("0:00"), "label \(ring.label)")

        // 3 s grace, then the engine forgets the rest and the label reads the elapsed time.
        let elapsed = NSPredicate(format: "label ENDSWITH 'elapsed'")
        expectation(for: elapsed, evaluatedWith: ring)
        waitForExpectations(timeout: 12)
        XCTAssertTrue(ring.label.hasPrefix("Resume workout, "), "label \(ring.label)")
    }

    /// A rest that ends while the workout is minimised and a past workout is pushed (no resume ring there): the root's
    /// watcher still forgets the over rest at expiry plus grace. Proof: back on the root the ring already reads the elapsed
    /// time, not "rest over" (the ring itself no longer forgets anything).
    @MainActor
    func testRestIsForgottenOnAPushedScreenWhileMinimised() throws {
        let app = XCUIApplication.launchedInActiveWorkout(["-sampleRestSeconds", "6", "-seedOldWorkout"])
        let any = app.descendants(matching: .any)
        let ring = app.buttons["resume.ring"].firstMatch
        app.buttons["cover.minimise"].firstMatch.tap()
        XCTAssertTrue(ring.waitForExistence(timeout: 10))
        XCTAssertTrue(ring.label.contains("rest "), "no rest running: \(ring.label)")

        app.selectTab("tab.history", label: "History")
        let row = any.matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.row.' AND label BEGINSWITH 'Old Backfill Workout'")
        )
        .firstMatch
        for _ in 0..<8 {
            if row.waitForExistence(timeout: 2) && row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.exists, "the seeded old workout is missing from History")
        row.tap()
        XCTAssertTrue(any["history.detail"].waitForExistence(timeout: 5), "the row did not open the detail")
        ring.assertStaysAbsent(for: 1, "a resume ring shows on the pushed detail")

        // The rest ends 6 s after launch and the grace is 3 s: stay on the pushed screen well past both.
        Thread.sleep(forTimeInterval: 12)

        let back = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "no back button on the pushed detail")
        back.tap()
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 5))
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        XCTAssertTrue(
            ring.label.hasSuffix("elapsed"),
            "the over rest was not forgotten on the pushed screen: \(ring.label)"
        )
    }
}
