import XCTest

/// The rest ring (task 2.5): the idle menu starts presets and customs, the running ring opens the sheet whose +10 s and
/// Skip act on the rest, and a started custom length is listed afterwards.
final class RestRingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// `m:ss` (or `h:mm:ss`) to seconds; nil when the text is not a time.
    private func seconds(from text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.split(separator: " ").first.map(String.init)?.split(separator: ":").compactMap { Int($0) }
        guard let parts, !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    @MainActor
    func testPresetAdjustSkipAndCustom() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-startSampleWorkout", "-openWorkoutCover"]
        app.launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.activeWorkout"].waitForExistence(timeout: 15))

        let ring = app.buttons["rest.ring"].firstMatch
        let skip = app.buttons["rest.skip"].firstMatch
        let plus10 = app.buttons["rest.plus10"].firstMatch
        let sheetRing = any["rest.sheet.ring"].firstMatch

        // The launch argument also starts a 300 s rest: skip it through the ring and its sheet.
        XCTAssertTrue(ring.waitForExistence(timeout: 10))
        ring.tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5), "sheet did not close after Skip")

        // Idle menu -> 1:00 starts a rest.
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        ring.tap()
        let preset60 = app.buttons["rest.preset.60"].firstMatch
        XCTAssertTrue(preset60.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["rest.preset.30"].exists)
        XCTAssertTrue(app.buttons["rest.preset.120"].exists)
        XCTAssertTrue(app.buttons["rest.preset.180"].exists)
        XCTAssertTrue(app.buttons["rest.custom"].exists)
        preset60.tap()
        expectation(for: NSPredicate(format: "value != nil AND value != ''"), evaluatedWith: ring)
        waitForExpectations(timeout: 5)
        let started = try XCTUnwrap(
            seconds(from: ring.value as? String),
            "ring value \(String(describing: ring.value))"
        )
        XCTAssertLessThanOrEqual(started, 60)
        XCTAssertGreaterThan(started, 40)

        // Sheet: +10 s raises the total and the remaining time.
        ring.tap()
        XCTAssertTrue(plus10.waitForExistence(timeout: 5))
        XCTAssertTrue(sheetRing.waitForExistence(timeout: 5))
        let before = try XCTUnwrap(seconds(from: sheetRing.value as? String))
        XCTAssertLessThanOrEqual(before, 60)
        plus10.tap()
        expectation(
            for: NSPredicate(format: "value ENDSWITH 'of 1:10'"),
            evaluatedWith: sheetRing
        )
        waitForExpectations(timeout: 5)
        let after = try XCTUnwrap(seconds(from: sheetRing.value as? String))
        XCTAssertGreaterThan(after, before)
        XCTAssertLessThanOrEqual(after, 70)

        // Skip closes the sheet and brings the idle menu back.
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        ring.tap()
        let custom = app.buttons["rest.custom"].firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 5), "idle menu did not return after Skip")

        // Custom... -> 0 min 45 sec -> Start.
        custom.tap()
        let start = app.buttons["rest.custom.start"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.element(boundBy: 1).waitForExistence(timeout: 5))
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: "0 min")
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: "45 sec")
        start.tap()
        XCTAssertTrue(start.waitForNonExistence(timeout: 5), "custom sheet did not close")
        expectation(for: NSPredicate(format: "value != nil AND value != ''"), evaluatedWith: ring)
        waitForExpectations(timeout: 5)
        let custom45 = try XCTUnwrap(seconds(from: ring.value as? String))
        XCTAssertLessThanOrEqual(custom45, 45)
        XCTAssertGreaterThan(custom45, 25)

        // After Skip the custom 0:45 is listed in the menu.
        ring.tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        ring.tap()
        let preset45 = app.buttons["rest.preset.45"].firstMatch
        XCTAssertTrue(preset45.waitForExistence(timeout: 5), "custom 0:45 not listed")
        XCTAssertEqual(preset45.label, "Rest 0:45")
    }
}
