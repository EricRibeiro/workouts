import XCTest

/// The opt-in Fitness enrichment wired into the app (PLAN 7.1b e3b): off by default; the Settings toggle turns it on, a
/// finished workout then picks up the canned Fitness workout from `-healthFixture full` (its History row then shows the
/// active calories: the row's label says "N active calories", the text on screen "N kcal"); turning it off can remove what
/// was added. Nothing here touches the real Health store: plain `-uiTesting` has no source at all. Shared helpers:
/// `Support/XCTestCase+HealthEnrichment.swift`.
///
/// This suite: turning off and choosing Keep leaves the data; the one-time backfill of an old workout.
final class HealthEnrichmentKeepUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTurningOffAndKeepingLeavesTheData() throws {
        let app = healthLaunchWithRunningWorkout()
        healthInSettings(app) { healthFlip(healthFitnessToggle(app)) }
        healthFinishWorkout(app)
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(healthFitnessRow(app).exists)

        app.selectTab("tab.workout", label: "Workout")
        healthInSettings(app) {
            let toggle = healthFitnessToggle(app)
            healthFlip(toggle)
            XCTAssertTrue(app.alerts["Turn Off Apple Fitness?"].waitForExistence(timeout: 5))
            app.alerts.buttons["settings.health.keep"].firstMatch.tap()
            healthExpectValue(toggle, "0")
        }
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(healthFitnessRow(app).exists, "Keep Fitness Data dropped the data")
    }

    /// PLAN 7.1b g: a workout that finished 30 days ago (past the routine lookup's 7-day give-up) gets its Fitness data when
    /// the toggle goes on, through the one-time backfill. The row's label then says "N active calories".
    @MainActor
    func testTurningOnBackfillsAnOldWorkout() throws {
        let app = XCUIApplication.launchedForTesting(["-healthFixture", "full", "-seedOldWorkout"])

        app.selectTab("tab.history", label: "History")
        let oldRow = "identifier BEGINSWITH 'history.row.' AND label BEGINSWITH 'Old Backfill Workout'"
        XCTAssertTrue(healthHistoryRow(app, oldRow).exists, "the seeded old workout is missing from History")
        XCTAssertFalse(
            healthHistoryRow(app, oldRow + " AND label CONTAINS 'active calories'", timeout: 2).exists,
            "the old workout had Fitness data before the toggle went on"
        )

        app.selectTab("tab.workout", label: "Workout")
        healthInSettings(app) {
            let toggle = healthFitnessToggle(app)
            healthFlip(toggle)
            healthExpectValue(toggle, "1")
        }
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(
            healthHistoryRow(app, oldRow + " AND label CONTAINS 'active calories'", timeout: 15).exists,
            "the backfill never gave the old workout its Fitness data"
        )
    }
}
