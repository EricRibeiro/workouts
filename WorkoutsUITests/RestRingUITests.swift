import XCTest

/// The rest ring (task 2.5): the idle menu starts presets and customs, the running ring opens the sheet whose +10 s and
/// Skip act on the rest, and a started custom length is listed afterwards.
final class RestRingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPresetAdjustSkipAndCustom() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let any = app.descendants(matching: .any)

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
        expectation(for: NSPredicate(format: "label CONTAINS ', '"), evaluatedWith: ring)
        waitForExpectations(timeout: 5)
        let started = try XCTUnwrap(
            seconds(from: ringTime(ring)),
            "ring label \(ring.label)"
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
        expectation(for: NSPredicate(format: "label CONTAINS ', '"), evaluatedWith: ring)
        waitForExpectations(timeout: 5)
        let custom45 = try XCTUnwrap(seconds(from: ringTime(ring)))
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

    /// Starts a rest of `seconds` from the idle ring's menu and waits until the ring shows it running ("Rest timer, m:ss").
    @MainActor
    private func startRest(_ seconds: Int, in app: XCUIApplication) {
        let ring = app.buttons["rest.ring"].firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 10), "no rest ring")
        XCTAssertEqual(ring.label, "Rest timer", "a rest was already running")
        ring.tap()
        let preset = app.buttons["rest.preset.\(seconds)"].firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5), "no \(seconds) s preset")
        preset.tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Rest timer, '"), evaluatedWith: ring)
        waitForExpectations(timeout: 15)
    }

    /// The running sheet left open while the rest expires goes away with it and does not reopen at the next rest.
    @MainActor
    func testRunningSheetClosesWithTheRestAndStaysClosedForTheNext() throws {
        let app = XCUIApplication.launchedInActiveWorkout(["-sampleNoRest"])
        let ring = app.buttons["rest.ring"].firstMatch
        let sheet = app.buttons["rest.plus10"].firstMatch
        startRest(60, in: app)
        ring.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "the running sheet did not open")
        // The rest expires (the Debug seam); after the 3 s grace the engine forgets it and the sheet must close with it.
        app.expireRestNow()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 25), "the sheet stayed open after the rest ended")

        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == 'Rest timer'"), evaluatedWith: ring)
        waitForExpectations(timeout: 10)
        ring.tap()
        let preset = app.buttons["rest.preset.60"].firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        preset.tap()
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Rest timer, '"), evaluatedWith: ring)
        waitForExpectations(timeout: 5)
        sheet.assertStaysAbsent(for: 2, "the sheet reopened by itself at the next rest")
    }

    /// A rest that expires reads "Rest over" through the grace, then the ring returns to idle. The success haptic and ok tint
    /// are timer-driven but cannot be asserted from XCUITest.
    @MainActor
    func testRestEndsAndRingReturnsToIdle() throws {
        let app = XCUIApplication.launchedInActiveWorkout(["-sampleNoRest"])
        let ring = app.buttons["rest.ring"].firstMatch
        startRest(30, in: app)
        app.expireRestNow()
        // The grace reads "Rest over" (an exact label: the idle label is also what a rest that never started shows)...
        expectation(for: NSPredicate(format: "label == 'Rest over'"), evaluatedWith: ring)
        waitForExpectations(timeout: 10)
        // ...and 3 s later the engine forgets the rest and the idle label is back.
        expectation(for: NSPredicate(format: "label == 'Rest timer'"), evaluatedWith: ring)
        waitForExpectations(timeout: 12)
        XCTAssertEqual(ring.label, "Rest timer")
    }

    /// A rest that ends while a set field has focus (the ring is out of the toolbar then) is still forgotten: the keyboard
    /// accessory's countdown goes away and focus stays. The cover's `RestExpiryWatcher` owns this, not the ring.
    @MainActor
    func testRestEndsWhileSetFieldHasFocus() throws {
        let app = XCUIApplication.launchedInActiveWorkout(["-sampleNoRest"])
        startRest(30, in: app)
        let weight = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.weight'")
        )
        .element(boundBy: 0)
        XCTAssertTrue(weight.waitForExistence(timeout: 10))
        weight.tap()
        let countdown = app.staticTexts["rest.keyboard.countdown"].firstMatch
        XCTAssertTrue(countdown.waitForExistence(timeout: 5), "no countdown in the keyboard accessory")
        // The rest expires (the Debug seam); 3 s grace + loop tick later it is forgotten.
        app.expireRestNow()
        XCTAssertTrue(countdown.waitForNonExistence(timeout: 20), "the over rest stayed in the keyboard accessory")
        XCTAssertTrue(app.buttons["setkeyboard.done"].firstMatch.exists, "focus left the set field")
    }
}
