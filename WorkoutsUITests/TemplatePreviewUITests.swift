import XCTest

/// The template preview and starting a workout (task 3.3): card -> preview -> Start Workout opens the logging screen, and
/// with a workout already running Start Workout and Empty Workout ask "Workout in progress". These use the real app with
/// the sample data (`-seedSampleData`, or `-startSampleWorkout` for a running workout), since the gallery has no engine.
final class TemplatePreviewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extra: String) -> XCUIApplication {
        let app = XCUIApplication.launchedForTesting([extra])
        return app
    }

    /// A dialog button by identifier, or by label (an action sheet's buttons lose their identifier).
    private func dialogButton(_ app: XCUIApplication, id: String, label: String) -> XCUIElement {
        let byID = app.buttons[id].firstMatch
        if byID.waitForExistence(timeout: 5) { return byID }
        return app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    func testCardOpensPreviewAndStartOpensTheLoggingScreen() throws {
        let app = launch("-seedSampleData")
        let any = app.descendants(matching: .any)
        let card = app.firstTemplateCard
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let name = card.label.components(separatedBy: ", ").first ?? ""
        card.tap()

        XCTAssertTrue(any["template.preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[name].firstMatch.exists, "the preview should be titled \(name)")
        XCTAssertTrue(
            app.buttons["template.exercise.about"].firstMatch.exists,
            "the preview should list the exercises with an About button"
        )
        let start = app.buttons["template.start"].firstMatch
        XCTAssertTrue(start.exists)
        XCTAssertTrue(start.isEnabled)
        XCTAssertEqual(start.label, "Start Workout")
        start.tap()

        XCTAssertTrue(any["screen.activeWorkout"].waitForExistence(timeout: 10), "Start should open the logging screen")
        XCTAssertTrue(any["template.preview"].waitForNonExistence(timeout: 5), "the sheet should be gone")
    }

    @MainActor
    func testAboutButtonOpensTheExerciseDetail() throws {
        let app = launch("-seedSampleData")
        let any = app.descendants(matching: .any)
        let card = app.firstTemplateCard
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(any["template.preview"].waitForExistence(timeout: 5))

        let about = app.buttons["template.exercise.about"].firstMatch
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.tap()

        XCTAssertTrue(
            any["exerciseDetail.name"].waitForExistence(timeout: 5),
            "the info button should open the exercise's detail in the info sheet"
        )
        let close = app.buttons["exerciseInfo.close"].firstMatch
        XCTAssertTrue(close.exists, "the info sheet has the same Close button as the workout's")
        close.tap()
        XCTAssertTrue(any["exerciseDetail.name"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(any["template.preview"].exists, "closing the info sheet returns to the preview")
    }

    @MainActor
    func testEmptyWorkoutWhileOneRunsAsksAndResumes() throws {
        let app = launch("-startSampleWorkout")
        let any = app.descendants(matching: .any)
        let add = app.buttons["toolbar.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        let empty = app.buttons["toolbar.add.emptyWorkout"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        empty.tap()

        XCTAssertTrue(app.staticTexts["Workout in progress"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'You are in the middle of'")).firstMatch
                .exists,
            "the message should name the running workout"
        )
        XCTAssertFalse(any["screen.activeWorkout"].exists, "the dialog comes before the cover")
        let resume = dialogButton(app, id: "start.resume", label: "Resume Workout")
        XCTAssertTrue(resume.exists)
        XCTAssertTrue(dialogButton(app, id: "start.discardAndStart", label: "Discard and Start New").exists)
        resume.tap()
        XCTAssertTrue(any["screen.activeWorkout"].waitForExistence(timeout: 10), "Resume should open the cover")
    }

    @MainActor
    func testStartFromPreviewWhileOneRunsCanDiscardAndStartNew() throws {
        let app = launch("-startSampleWorkout")
        let any = app.descendants(matching: .any)
        let card = app.firstTemplateCard
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        let start = app.buttons["template.start"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(app.staticTexts["Workout in progress"].firstMatch.waitForExistence(timeout: 5))
        let discard = dialogButton(app, id: "start.discardAndStart", label: "Discard and Start New")
        XCTAssertTrue(discard.exists)
        discard.tap()
        XCTAssertTrue(any["screen.activeWorkout"].waitForExistence(timeout: 10), "the new workout should open")
        XCTAssertTrue(any["template.preview"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testFinishingADifferingTemplateWorkoutAsksToUpdateTheTemplate() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let any = app.descendants(matching: .any)

        // Check one set; the rest are dropped on Finish, so the workout no longer matches its template's sets.
        let check = app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.check'")
        ).element(boundBy: 0)
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        check.tap()
        app.anyControl("cover.finish").tap()
        let finish = dialogButton(app, id: "finish.finish", label: "Finish Workout")
        XCTAssertTrue(finish.exists)
        finish.tap()

        XCTAssertTrue(any["screen.finishSummary"].waitForExistence(timeout: 10))
        app.buttons["summary.done"].firstMatch.tap()
        XCTAssertTrue(any["screen.finishSummary"].waitForNonExistence(timeout: 10))

        let alert = app.alerts["Update Template?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(
            dialogButton(app, id: "updateTemplate.templateAndValues", label: "Update Template and Values").exists
        )
        XCTAssertTrue(alert.buttons["Keep Original Template"].exists)
        let valuesOnly = dialogButton(app, id: "updateTemplate.valuesOnly", label: "Update Values Only")
        XCTAssertTrue(valuesOnly.exists)
        valuesOnly.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
    }
}
