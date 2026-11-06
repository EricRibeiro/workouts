import XCTest

/// The opt-in Fitness enrichment wired into the app (PLAN 7.1b e3b): off by default; the Settings toggle turns it on, a
/// finished workout then picks up the canned Fitness workout from `-healthFixture full` (its History row then shows the
/// active calories: the row's label says "N active calories", the text on screen "N kcal"); turning it off can remove what
/// was added. Nothing here touches the real Health store: plain `-uiTesting` has no source at all. Shared helpers:
/// `Support/XCTestCase+HealthEnrichment.swift`.
///
/// This suite: the defaults (off, no lookup, the Settings section only where Health is available).
final class HealthEnrichmentUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOffByDefaultNothingIsAdded() throws {
        let app = healthLaunchWithRunningWorkout()
        healthInSettings(app) {
            XCTAssertEqual(healthFitnessToggle(app).value as? String, "0")
        }
        healthFinishWorkout(app)
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(healthAnyRow(app).exists, "the finished workout is missing from History")
        // Nothing on screen says "the lookup finished", so absence is a bounded wait: a (wrongly) triggered lookup has this long
        // to put its calories on the row.
        XCTAssertFalse(healthFitnessRow(app, timeout: 5).exists, "Fitness data was added while the setting is off")
    }

    @MainActor
    func testSettingsSectionOnlyWhereHealthIsAvailable() throws {
        let without = XCUIApplication.launchedPreview("Settings", waitingFor: "screen.settings")
        XCTAssertTrue(without.anyControl("settings.weeklyGoal").waitForExistence(timeout: 5))
        for _ in 0..<3 { without.swipeUp() }
        XCTAssertFalse(without.anyControl("settings.health.enabled").exists)
    }
}
