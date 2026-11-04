import XCTest

/// The Finish flow on the logging screen (task 2.8): with nothing checked Finish asks "Nothing logged yet" and Keep Going
/// stays; with a checked set and unchecked sets that have values, Complete Unfinished Sets saves and closes the cover.
final class FinishUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFinishNothingLoggedThenCompleteUnfinished() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-startSampleWorkout", "-openWorkoutCover"]
        app.launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["screen.activeWorkout"].waitForExistence(timeout: 15))

        let finish = app.buttons["cover.finish"].firstMatch
        let keepGoing = app.buttons.matching(NSPredicate(format: "label == 'Keep Going'")).firstMatch
        let keepLogging = app.buttons.matching(NSPredicate(format: "label == 'Keep Logging'")).firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        finish.tap()
        XCTAssertTrue(app.staticTexts["Nothing logged yet"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["finish.discardWorkout"].firstMatch.exists)
        // Keep Going is the cancel role. On a compact-width action sheet it is a button (the system drops its
        // identifier, so match the label); in a popover (regular width) the system omits it and tapping outside dismisses.
        if keepGoing.exists {
            keepGoing.tap()
        } else {
            app.otherElements["PopoverDismissRegion"].firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["finish.discardWorkout"].firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(any["screen.activeWorkout"].exists)

        let check = app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.check'")
        ).element(boundBy: 0)
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        check.tap()

        // Only unchecked sets without values left: the lighter "N sets are not checked" dialog, nothing to complete.
        finish.tap()
        XCTAssertTrue(
            app.buttons["finish.finish"].firstMatch.waitForExistence(timeout: 5),
            "unchecked-without-values dialog missing"
        )
        if keepLogging.exists {
            keepLogging.tap()
        } else {
            app.otherElements["PopoverDismissRegion"].firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["finish.finish"].firstMatch.waitForNonExistence(timeout: 5))

        // A value typed into another unchecked set turns it into "Finish Workout?".
        let weight = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.weight'")
        ).element(boundBy: 1)
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        weight.tap()
        weight.typeText("50")

        finish.tap()
        let complete = app.buttons["finish.complete"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 5), "Finish Workout? dialog missing")
        complete.tap()

        XCTAssertTrue(any["screen.workout"].waitForExistence(timeout: 10))
        XCTAssertTrue(any["screen.activeWorkout"].waitForNonExistence(timeout: 10))
    }
}
