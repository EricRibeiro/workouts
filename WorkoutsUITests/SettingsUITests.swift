import XCTest

/// The Settings form on the gallery entry `Settings` (task 5.7a): the controls respond and carry their ids.
final class SettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Launch-argument defaults override the stored values, so a run never depends on an earlier one.
        app.launchArguments += [
            "-uiTesting", "-preview", "Settings",
            "-defaultUnit", "lb", "-defaultRestSeconds", "90", "-weeklyGoal", "3", "-e1rmFormula", "epley",
        ]
        app.launch()
        return app
    }

    @MainActor
    func testUnitSegmentedControlSwitchesToKg() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.settings"].waitForExistence(timeout: 10))

        let unit = app.segmentedControls["settings.defaultUnit"]
        XCTAssertTrue(unit.waitForExistence(timeout: 5), "no unit control")
        XCTAssertTrue(unit.buttons["lb"].isSelected)
        unit.buttons["kg"].tap()
        XCTAssertTrue(unit.buttons["kg"].isSelected)
        XCTAssertFalse(unit.buttons["lb"].isSelected)

        let formula = app.segmentedControls["settings.e1rmFormula"]
        XCTAssertTrue(formula.exists)
        formula.buttons["Brzycki"].tap()
        XCTAssertTrue(formula.buttons["Brzycki"].isSelected)
    }

    @MainActor
    func testWeeklyGoalStepperIncrements() throws {
        let app = launch()
        let stepper = app.steppers["settings.weeklyGoal"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 10), "no weekly goal stepper")
        XCTAssertEqual(stepper.value as? String, "3 workouts per week")
        stepper.buttons.element(boundBy: 1).tap()
        XCTAssertEqual(stepper.value as? String, "4 workouts per week")
    }

    @MainActor
    func testRestPickerShowsOneThirtyAndRowsExist() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        let rest = any["settings.defaultRestSeconds"]
        XCTAssertTrue(rest.waitForExistence(timeout: 10), "no rest picker")
        let value = (rest.value as? String) ?? ""
        XCTAssertTrue(rest.label.contains("1:30") || value.contains("1:30"), "label \(rest.label), value \(value)")

        XCTAssertTrue(any["settings.keepScreenOn"].exists, "keepScreenOn")
        XCTAssertTrue(any["settings.downloadAllVideos"].exists, "downloadAllVideos")
        // The iCloud row sits below the fold on the closed display; the list only builds rows near the viewport.
        let icloud = any["settings.iCloudStatus"]
        for _ in 0..<4 where !icloud.exists { app.swipeUp() }
        XCTAssertTrue(icloud.exists, "iCloudStatus")
    }

    /// The file pickers cannot be driven reliably, so this only proves the rows exist and Export opens the share sheet
    /// (import, export and re-import are proven by the kit's `ImportExportFlowTests`).
    @MainActor
    func testDataRowsExistAndExportOpensTheShareSheet() throws {
        let app = launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.settings"].waitForExistence(timeout: 10))
        let export = app.buttons["settings.export"].firstMatch
        for _ in 0..<5 where !export.isHittable { app.swipeUp() }
        XCTAssertTrue(export.exists, "no Export row")
        XCTAssertTrue(app.buttons["settings.import"].firstMatch.exists, "no Import row")

        export.tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "no share sheet")
        // Dismiss it with its close button when it exposes one, else by tapping the dimmed area above the sheet.
        let close = app.buttons.matching(NSPredicate(format: "label ==[c] 'close'")).firstMatch
        if close.waitForExistence(timeout: 3) {
            close.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
        }
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10), "share sheet still showing")
        XCTAssertTrue(any["screen.settings"].exists)
    }
}
