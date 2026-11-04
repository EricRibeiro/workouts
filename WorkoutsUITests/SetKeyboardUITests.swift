import XCTest

/// The set keyboard's accessory group on the gallery entry `SetRow` (task 2.2b): +step, Next and Done.
final class SetKeyboardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func value(_ element: XCUIElement) -> String {
        (element.value as? String) ?? ""
    }

    /// `hasKeyboardFocus` is not exposed to Swift on `XCUIElement`, but the attribute is readable by key.
    private func hasFocus(_ element: XCUIElement) -> Bool {
        element.exists && (element.value(forKey: "hasKeyboardFocus") as? Bool ?? false)
    }

    @MainActor
    func testStepNextAndDone() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-preview", "SetRow"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["screen.setRowDemo"].waitForExistence(timeout: 10))

        // Row 1: weight 60 kg, reps 8 (a normal weighted set, so the step is 1.25 kg).
        let weight = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.weight'")
        )
        .element(boundBy: 0)
        let reps = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.reps'")
        )
        .element(boundBy: 0)
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertEqual(value(weight), "60")
        XCTAssertEqual(value(reps), "8")

        weight.tap()
        let plus = app.buttons["setkeyboard.plus"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "keyboard group missing")
        XCTAssertTrue(hasFocus(weight))

        // +step: one step of 1.25 kg.
        plus.tap()
        XCTAssertEqual(value(weight), "61.25")
        app.buttons["setkeyboard.minus"].firstMatch.tap()
        XCTAssertEqual(value(weight), "60")
        plus.tap()
        XCTAssertEqual(value(weight), "61.25")

        // Next: weight -> reps.
        app.buttons["setkeyboard.next"].firstMatch.tap()
        XCTAssertTrue(hasFocus(reps), "focus did not move to reps")
        XCTAssertFalse(hasFocus(weight))
        plus.tap()
        XCTAssertEqual(value(reps), "9")
        XCTAssertEqual(value(weight), "61.25")

        // Done closes the keyboard and does not check the set.
        app.buttons["setkeyboard.done"].firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertFalse(hasFocus(reps))
        XCTAssertEqual(value(reps), "9")
    }
}
