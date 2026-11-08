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
        // The fixture source counts its lookups, so "none ran" is exact however slow a wrong one would have been.
        let lookups = app.descendants(matching: .any)["debug.health.lookups"].firstMatch
        XCTAssertTrue(lookups.waitForExistence(timeout: 5), "no lookup counter")
        XCTAssertEqual(lookups.value as? String, "0", "a Health lookup ran while the setting is off")
        healthFitnessRow(app, timeout: 1).assertStaysAbsent(for: 1, "Fitness data was added while the setting is off")
        // A lookup fired at finish time could still be in flight at the first read; the absence wait above gives it room.
        XCTAssertEqual(lookups.value as? String, "0", "a Health lookup ran late while the setting is off")
    }

    @MainActor
    func testSettingsSectionOnlyWhereHealthIsAvailable() throws {
        let without = XCUIApplication.launchedPreview("Settings", waitingFor: "screen.settings")
        XCTAssertTrue(without.anyControl("settings.weeklyGoal").waitForExistence(timeout: 5))
        // The Debug section is the last one: once its button is on screen the whole form has been scrolled past.
        let last = without.anyControl("settings.loadSampleData")
        for _ in 0..<5 where !last.exists || !last.isHittable { without.swipeUp() }
        XCTAssertTrue(last.waitForExistence(timeout: 5), "the last Settings row never came into view")
        without.anyControl("settings.health.enabled").assertStaysAbsent(for: 1, "Health row shown without a source")
    }
}
