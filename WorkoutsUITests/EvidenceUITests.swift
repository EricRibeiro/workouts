import XCTest

/// Look-at-it screenshots of states no test inspected (single folder, Unfiled, folder menu, selected exercise on the open
/// Duo; calendar today ring; workout detail with Health tiles). Not assertions: each test drives to the state and writes a PNG.
/// Skips itself unless the runner sees `EVIDENCE=1` (`TEST_RUNNER_EVIDENCE=1 ./dev ui-test EvidenceUITests/<test>()`, with
/// `DEV_POSE=open-wide` for the open ones), so the normal suites never run it.
final class EvidenceUITests: XCTestCase {
    private static let outDir =
        "/private/tmp/claude-501/-Users-ericribeiro-Projects-workouts/307a787d-b588-4272-bc9f-40651908dc0d/scratchpad/seen"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(ProcessInfo.processInfo.environment["EVIDENCE"] != "1", "run with TEST_RUNNER_EVIDENCE=1")
    }

    @MainActor
    private func save(_ name: String) throws {
        // The open Duo has two displays and `main` can be the dark one: take the largest non-black capture.
        let shots = ([XCUIScreen.main] + XCUIScreen.screens).map { $0.screenshot().pngRepresentation }
        let png = shots.max { $0.count < $1.count } ?? Data()
        let url = URL(fileURLWithPath: "\(Self.outDir)/\(name).png")
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: url)
        } catch {
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("write \(url.path) failed: \(error)")
        }
    }

    // MARK: Workout tab helpers

    @MainActor
    private func launchWorkout() -> XCUIApplication {
        let app = XCUIApplication.launchedForTesting(["-seedSampleData"], waitingFor: "screen.workout", timeout: 15)
        XCTAssertTrue(app.firstTemplateCard.waitForExistence(timeout: 10))
        return app
    }

    private func card(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'workout.template.' AND label BEGINSWITH %@", name)
        ).firstMatch
    }

    private func header(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format:
                    "identifier BEGINSWITH 'workout.folder.' AND identifier ENDSWITH '.toggle' AND label BEGINSWITH %@",
                name
            )
        ).firstMatch
    }

    /// Long-press `template`'s card, Move, then the folder called `destination` ("No Folder" for none).
    @MainActor
    private func move(_ app: XCUIApplication, _ template: String, to destination: String) {
        let target = card(app, template)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "no \(template) card")
        target.press(forDuration: 1.0)
        let menu = app.buttons["templateCard.move"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "no Move item")
        menu.tap()
        Thread.sleep(forTimeInterval: 1)
        let item = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH 'workout.')", destination)
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no \(destination) in the Move menu: \(app.debugDescription)")
        item.tap()
        _ = item.waitForNonExistence(timeout: 5)
    }

    @MainActor
    private func deleteEmptyFolder(_ app: XCUIApplication, _ name: String) {
        let folder = header(app, name)
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        folder.press(forDuration: 1.2)
        let delete = app.buttons["workout.folder.delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirm = app.buttons["workout.folder.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(folder.waitUntilGone(timeout: 5), "\(name) not deleted")
    }

    private func settle() { Thread.sleep(forTimeInterval: 1.0) }

    // MARK: States

    @MainActor
    func testSingleFolderOpen() throws {
        let app = launchWorkout()
        move(app, "Legs", to: "Upper Body")
        deleteEmptyFolder(app, "Lower Body")
        settle()
        try save("single-folder-open")
    }

    @MainActor
    func testUnfiledOpen() throws {
        let app = launchWorkout()
        move(app, "Legs", to: "No Folder")
        deleteEmptyFolder(app, "Lower Body")
        settle()
        try save("unfiled-open")
    }

    @MainActor
    func testFolderMenuOpen() throws {
        let app = launchWorkout()
        let upper = header(app, "Upper Body")
        XCTAssertTrue(upper.waitForExistence(timeout: 10))
        upper.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["workout.folder.moveDown"].firstMatch.waitForExistence(timeout: 5), "no Move Later")
        settle()
        try save("folder-menu-open")
    }

    @MainActor
    func testExerciseSelectedOpen() throws {
        let app = XCUIApplication.launchedForTesting(["-seedSampleData"], waitingFor: "screen.workout", timeout: 15)
        app.selectTab("tab.exercises", label: "Exercises")
        XCTAssertTrue(app.descendants(matching: .any)["screen.exercises"].waitForExistence(timeout: 10))
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'exercises.row.'")
        )
        let second = rows.element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        second.tap()
        settle()
        try save("exercise-selected-open")
    }

    @MainActor
    func testCalendarToday() throws {
        let app = XCUIApplication.launchedForTesting(["-seedSampleData"], waitingFor: "screen.workout", timeout: 15)
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(app.descendants(matching: .any)["screen.history"].waitForExistence(timeout: 10))
        let open = app.buttons["history.calendar"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.calendar"].waitForExistence(timeout: 5))
        settle()
        try save("calendar-today")

        let marked = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'calendar.day.' AND label MATCHES '.*[0-9]+ workouts?'")
        )
        XCTAssertTrue(marked.firstMatch.waitForExistence(timeout: 5), "no marked day this month")
        let today = Calendar.current.component(.day, from: Date())
        let other = marked.allElementsBoundByIndex.first { !$0.label.contains(" \(today),") } ?? marked.firstMatch
        other.tap()
        Thread.sleep(forTimeInterval: 0.3)
        try save("calendar-selected")
    }

    @MainActor
    func testDetailHealth() throws {
        let app = healthLaunchWithRunningWorkout()
        healthInSettings(app) { healthFlip(healthFitnessToggle(app)) }
        healthFinishWorkout(app)
        app.selectTab("tab.history", label: "History")
        let row = healthFitnessRow(app, timeout: 20)
        XCTAssertTrue(row.exists, "no Health-enriched history row")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["history.detail"].waitForExistence(timeout: 8))
        settle()
        try save("detail-health")
    }

    @MainActor
    func testDetailHealthOpen() throws {
        let app = healthLaunchWithRunningWorkout()
        healthInSettings(app) {
            // The open Duo's Settings is a centred sheet: scroll inside it, a swipe on the app may miss it.
            let sheet = app.descendants(matching: .any)["screen.settings"]
            let toggle = app.switches["settings.health.enabled"]
            for _ in 0..<6 where !toggle.exists || !toggle.isHittable { sheet.swipeUp() }
            healthFlip(toggle)
        }
        healthFinishWorkout(app)
        app.selectTab("tab.history", label: "History")
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.row.'")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no history row")
        Thread.sleep(forTimeInterval: 4)
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["history.detail"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 3)
        try save("detail-open")
    }
}
