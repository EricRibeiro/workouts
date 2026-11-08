import XCTest

/// The Live Activity's `workouts://workout` link (banner and Dynamic Island) brings the minimised workout's cover back.
/// The app launches with the sample workout running and no cover (no `-openWorkoutCover`), so only the link can open it,
/// and the URL is delivered by the system, like a tap on the activity (`XCUIApplication.open` relaunches the app).
final class OpenWorkoutURLUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Opens `string` through the system, tapping through its "Open in Workouts?" confirmation when it appears.
    @MainActor
    private func openLink(_ string: String) throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: string)))
        let confirm = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Open"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
    }

    @MainActor
    func testWorkoutLinkReopensTheMinimisedCover() throws {
        let app = XCUIApplication.launchedForTesting(["-startSampleWorkout"], waitingFor: "screen.workout", timeout: 15)
        let any = app.descendants(matching: .any)
        XCTAssertTrue(app.buttons["resume.ring"].firstMatch.waitForExistence(timeout: 10), "no minimised workout")
        XCTAssertFalse(any["screen.activeWorkout"].exists)

        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 10))

        try openLink("workouts://workout")
        XCTAssertTrue(
            any["screen.activeWorkout"].waitForExistence(timeout: 10),
            "workouts://workout did not open the cover"
        )
    }

    /// A tab's own sheet (History's Calendar) is up when the link arrives: the sheet is left alone (it may hold typed
    /// input), and the person is never left with neither the cover nor the resume ring.
    @MainActor
    func testWorkoutLinkWithATabSheetOpenLeavesTheCoverOrTheRing() throws {
        let app = XCUIApplication.launchedForTesting(["-startSampleWorkout"], waitingFor: "screen.workout", timeout: 15)
        let any = app.descendants(matching: .any)
        XCTAssertTrue(app.buttons["resume.ring"].firstMatch.waitForExistence(timeout: 10), "no minimised workout")
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 10))
        app.buttons["history.calendar"].tap()
        XCTAssertTrue(any["screen.calendar"].waitForExistence(timeout: 5), "the calendar sheet did not open")

        try openLink("workouts://workout")
        let cover = any["screen.activeWorkout"].waitForExistence(timeout: 10)
        // Whatever happens to the cover, the person is never left with neither it nor the ring.
        XCTAssertTrue(cover || app.buttons["resume.ring"].firstMatch.exists, "neither the cover nor the resume ring")
    }

    /// The link arrives while a full-screen editor (past workout, template) holds an unsaved edit. The editor is never
    /// closed by it: it stays up, edit intact, with no cover over it. Cancelling it (Discard) then presents the cover.
    @MainActor
    private func assertEditorKeptThenCoverAfterCancel(
        _ app: XCUIApplication,
        screen: String,
        cancel: String,
        editIsIntact: () -> Bool
    ) {
        let any = app.descendants(matching: .any)
        app.activate()
        let cover = any["screen.activeWorkout"]
        XCTAssertTrue(any[screen].waitForExistence(timeout: 5), "the link closed the editor")
        cover.assertStaysAbsent(for: 4, "the cover presented over the open editor")
        XCTAssertTrue(any[screen].exists, "the link closed the editor")
        XCTAssertTrue(editIsIntact(), "the link lost the unsaved edit")

        app.buttons[cancel].tap()
        let discard = app.buttons["Discard Changes"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "no unsaved-changes dialog")
        XCTAssertFalse(cover.exists, "the cover presented before the editor closed")
        discard.tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 10), "the deferred cover did not present after the editor closed")
        XCTAssertTrue(any[screen].waitUntilGone(timeout: 5), "the editor is still up under the cover")
    }

    @MainActor
    func testWorkoutLinkWithThePastEditorOpenWaitsForItThenOpensTheCover() throws {
        let app = XCUIApplication.launchedForTesting(["-startSampleWorkout"], waitingFor: "screen.workout", timeout: 15)
        let any = app.descendants(matching: .any)
        XCTAssertTrue(app.buttons["resume.ring"].firstMatch.waitForExistence(timeout: 10), "no minimised workout")
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 10))
        let rows = any.matching(NSPredicate(format: "identifier BEGINSWITH 'history.row.'"))
        let first = rows.element(boundBy: 0)
        for _ in 0..<8 {
            if first.waitForExistence(timeout: 2) && first.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(first.exists, "no history rows")
        first.press(forDuration: 1.0)
        let edit = app.buttons["history.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "no Edit in the context menu")
        edit.tap()
        XCTAssertTrue(any["screen.pastEditor"].waitForExistence(timeout: 5), "Edit did not open the editor")
        app.steppers["pastEditor.duration.stepper"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["pastEditor.save"].isEnabled, "Save is disabled after an edit")

        try openLink("workouts://workout")
        assertEditorKeptThenCoverAfterCancel(app, screen: "screen.pastEditor", cancel: "pastEditor.cancel") {
            app.buttons["pastEditor.save"].isEnabled
        }
    }

    @MainActor
    func testWorkoutLinkWithTheTemplateEditorOpenWaitsForItThenOpensTheCover() throws {
        let app = XCUIApplication.launchedForTesting(["-startSampleWorkout"], waitingFor: "screen.workout", timeout: 15)
        let any = app.descendants(matching: .any)
        XCTAssertTrue(app.buttons["resume.ring"].firstMatch.waitForExistence(timeout: 10), "no minimised workout")
        let card = app.firstTemplateCard
        XCTAssertTrue(card.waitForExistence(timeout: 10), "no template cards")
        card.tap()
        XCTAssertTrue(any["template.preview"].waitForExistence(timeout: 5), "the card did not open the preview")
        let editButton = app.buttons["template.edit"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 5), "no Edit item in the preview")
        editButton.tap()
        XCTAssertTrue(any["screen.templateEditor"].waitForExistence(timeout: 10), "Edit did not open the editor")
        let weight = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.weight'")
        )
        .element(boundBy: 0)
        XCTAssertTrue(weight.waitForExistence(timeout: 5), "no weight field")
        let before = (weight.value as? String) ?? ""
        weight.tap()
        let plus = app.buttons["setkeyboard.plus"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "keyboard group missing")
        plus.tap()
        let edited = (weight.value as? String) ?? ""
        XCTAssertNotEqual(before, edited, "the step did not change the weight")
        app.buttons["setkeyboard.done"].firstMatch.tap()

        try openLink("workouts://workout")
        assertEditorKeptThenCoverAfterCancel(app, screen: "screen.templateEditor", cancel: "templateEditor.cancel") {
            (weight.value as? String) == edited
        }
    }

    @MainActor
    func testUnknownLinkIsIgnored() throws {
        let app = XCUIApplication.launchedForTesting(["-startSampleWorkout"], waitingFor: "screen.workout", timeout: 15)
        let any = app.descendants(matching: .any)
        XCTAssertTrue(app.buttons["resume.ring"].firstMatch.waitForExistence(timeout: 10), "no minimised workout")
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 10))

        try openLink("workouts://nowhere")
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 5), "the app left the History tab")
        any["screen.activeWorkout"].assertStaysAbsent(for: 3, "an unknown link opened the cover")
        XCTAssertTrue(any["screen.history"].exists, "the app left the History tab")
    }
}
