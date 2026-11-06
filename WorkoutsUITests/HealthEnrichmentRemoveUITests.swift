import XCTest

/// The opt-in Fitness enrichment wired into the app (PLAN 7.1b e3b): off by default; the Settings toggle turns it on, a
/// finished workout then picks up the canned Fitness workout from `-healthFixture full` (its History row then shows the
/// active calories: the row's label says "N active calories", the text on screen "N kcal"); turning it off can remove what
/// was added. Nothing here touches the real Health store: plain `-uiTesting` has no source at all. Shared helpers:
/// `Support/XCTestCase+HealthEnrichment.swift`.
///
/// This suite: turning on adds the Fitness data; turning off and choosing Remove clears it (Cancel keeps it on).
final class HealthEnrichmentRemoveUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTurningOnThenFinishingAddsFitnessAndRemoveClearsIt() throws {
        let app = healthLaunchWithRunningWorkout()
        healthInSettings(app) {
            let toggle = healthFitnessToggle(app)
            healthFlip(toggle)
            healthExpectValue(toggle, "1")
        }
        healthFinishWorkout(app)
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(healthFitnessRow(app).exists, "the finished workout never got its Fitness data")

        // Off, then Cancel: stays on and keeps the data.
        app.selectTab("tab.workout", label: "Workout")
        healthInSettings(app) {
            let toggle = healthFitnessToggle(app)
            healthFlip(toggle)
            XCTAssertTrue(app.alerts["Turn Off Apple Fitness?"].waitForExistence(timeout: 5))
            app.alerts.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(app.alerts["Turn Off Apple Fitness?"].waitForNonExistence(timeout: 5))
            healthExpectValue(toggle, "1")
        }

        // Off, then Remove: the data goes.
        healthInSettings(app) {
            let toggle = healthFitnessToggle(app)
            healthFlip(toggle)
            XCTAssertTrue(app.alerts["Turn Off Apple Fitness?"].waitForExistence(timeout: 5))
            app.alerts.buttons["settings.health.remove"].firstMatch.tap()
            XCTAssertTrue(app.alerts["Turn Off Apple Fitness?"].waitForNonExistence(timeout: 5))
            healthExpectValue(toggle, "0")
        }
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(healthAnyRow(app).exists)
        XCTAssertFalse(healthFitnessRow(app, timeout: 3).exists, "Remove Fitness Data left the data in place")
    }
}
