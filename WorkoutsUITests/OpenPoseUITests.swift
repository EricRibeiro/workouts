import XCTest

/// The logging cover on the open Duo (PLAN 7c.11): `DEV_POSE=open-wide ./dev ui-test OpenPoseUITests` opens the hinge before
/// launch and restores closed-portrait afterwards. Out of the normal suites: it skips itself unless the runner sees
/// `DUO_POSE=open-wide`, so the full `./dev ui-test` counts its tests as skipped.
///
/// No rotation test: on the open inner display `XCUIDevice.shared.orientation = .landscapeLeft` leaves the window at 951×669
/// and the pane where it was (spike, 2026-11-09), so a placement change cannot be driven from XCUITest.
final class OpenPoseUITests: XCTestCase {
    private var pose: String { ProcessInfo.processInfo.environment["DUO_POSE"] ?? "" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        // The edges test also runs in the closed poses; the others need the open inner display.
        let runsInAnyPose = name.contains("testHistoryAndWorkoutShareEdges")
        let allowed = runsInAnyPose ? ["open-wide", "closed-portrait", "closed-landscape"] : ["open-wide"]
        try XCTSkipIf(
            !allowed.contains(pose),
            "run with DEV_POSE=open-wide ./dev ui-test OpenPoseUITests"
        )
    }

    @MainActor
    func testOpenWideShowsThePaneBesideTheTable() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(window.width, 951, accuracy: 1)
        XCTAssertEqual(window.height, 669, accuracy: 1)

        let pane = app.descendants(matching: .any)["cover.exercisePane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 10))
        let paneFrame = pane.waitUntilFrameSettles()
        // The pane starts at the middle of the safe area, not of the window: the system strip (clock, toolbar) takes about
        // 85 pt of the trailing edge, so the split sits near 433 pt.
        XCTAssertGreaterThanOrEqual(paneFrame.minX, 420, "pane \(paneFrame) is not beside the table")
        XCTAssertEqual(paneFrame.maxX, window.maxX, accuracy: 1)

        let weights = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'setrow.' AND identifier ENDSWITH '.weight'")
        )
        XCTAssertTrue(weights.firstMatch.waitForExistence(timeout: 10))
        for cell in weights.allElementsBoundByIndex where cell.exists {
            XCTAssertLessThanOrEqual(
                cell.frame.maxX,
                paneFrame.minX + 1,
                "set table cell \(cell.frame) reaches into the pane"
            )
        }
    }

    /// The Workout tab's two sample folders stack in one full-width column on the open Duo: the second header sits below the
    /// first folder's cards and both headers start at the same x.
    @MainActor
    func testOpenWideFoldersStackFullWidth() throws {
        let app = XCUIApplication.launchedPreview("Workout", waitingFor: "screen.workout")
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(window.width, 951, accuracy: 1)

        let headers = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'workout.folder.' AND identifier ENDSWITH '.toggle'")
        )
        XCTAssertTrue(headers.element(boundBy: 1).waitForExistence(timeout: 10), "fewer than two folders")
        let first = headers.element(boundBy: 0).waitUntilFrameSettles()
        let second = headers.element(boundBy: 1).waitUntilFrameSettles()
        XCTAssertEqual(first.minX, second.minX, accuracy: 2, "headers \(first) and \(second) do not share a left edge")
        let cards = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'workout.template.'")
        )
        let firstCardsBottom = cards.allElementsBoundByIndex.map(\.frame)
            .filter { $0.minY > first.maxY && $0.maxY <= second.minY }
            .map(\.maxY).max()
        XCTAssertNotNil(firstCardsBottom, "no template card between the two headers")
        XCTAssertGreaterThan(
            second.minY,
            firstCardsBottom ?? .infinity,
            "second folder \(second) is not below the first's cards"
        )
    }

    /// History and the Workout tab share their content edges in every Duo pose (`DEV_POSE=open-wide|closed-portrait|
    /// closed-landscape`): the first History card starts on the same x as the first template card and the right-most
    /// History card ends on the same x as the right-most template card.
    @MainActor
    func testHistoryAndWorkoutShareEdges() throws {
        func cardFrames(_ preview: String, screen: String, prefix: String) -> [CGRect] {
            let app = XCUIApplication.launchedPreview(preview, waitingFor: screen)
            let cards = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", prefix)
            )
            XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10), "no \(prefix) card in \(preview)")
            _ = cards.firstMatch.waitUntilFrameSettles()
            let window = app.windows.firstMatch.frame
            return cards.allElementsBoundByIndex.map(\.frame).filter { $0.width > 0 && window.intersects($0) }
        }
        // A compact History row's frame is its whole list cell, margins included, so the compact poses measure the dashboard
        // cards (which the first screen shows); the open display's month grid cards are real card frames.
        let historyPrefix = pose == "open-wide" ? "history.row." : "history.card."
        let history = cardFrames("History", screen: "screen.history", prefix: historyPrefix)
        let workout = cardFrames("Workout", screen: "screen.workout", prefix: "workout.template.")
        let historyFirst = history.sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }.first
        let workoutFirst = workout.sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }.first
        XCTAssertNotNil(historyFirst)
        XCTAssertNotNil(workoutFirst)
        XCTAssertEqual(
            historyFirst?.minX ?? 0,
            workoutFirst?.minX ?? -1,
            accuracy: 2,
            "first cards \(String(describing: historyFirst)) and \(String(describing: workoutFirst))"
        )
        let historyRight = history.map(\.maxX).max() ?? 0
        let workoutRight = workout.map(\.maxX).max() ?? -1
        XCTAssertEqual(historyRight, workoutRight, accuracy: 2, "right-most card edges differ")
    }

    /// The month title is part of its month's list row at regular width: scrolled to the second month, the first title is gone
    /// from the top and no title overlaps a card.
    @MainActor
    func testOpenWideHistoryMonthTitleScrollsAway() throws {
        let app = XCUIApplication.launchedPreview("History", waitingFor: "screen.history")
        let window = app.windows.firstMatch.frame
        let titles = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'history.month.'"))
        XCTAssertTrue(titles.element(boundBy: 0).waitForExistence(timeout: 10), "no month title")
        let firstID = titles.element(boundBy: 0).identifier
        let second = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.month.' AND identifier != %@", firstID)
        )
        .firstMatch
        var swipes = 0
        while swipes < 6, !(second.exists && second.frame.minY < window.midY && second.frame.minY > window.minY) {
            app.windows.firstMatch.swipeUp()
            swipes += 1
        }
        _ = second.waitUntilFrameSettles()
        XCTAssertTrue(
            second.exists && second.frame.minY < window.midY,
            "second month never reached the upper half (\(swipes) swipes)"
        )

        let first = app.staticTexts[firstID]
        XCTAssertTrue(
            !first.exists || !first.isHittable || first.frame.maxY <= window.minY || first.frame.minY < window.minY,
            "first month title \(firstID) is still on screen at \(first.frame)"
        )
        let listTop = app.collectionViews.firstMatch.frame.minY
        let cards = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.row.'")
        )
        .allElementsBoundByIndex.map(\.frame).filter { window.intersects($0) && $0.width > 0 }
        for title in titles.allElementsBoundByIndex where title.exists && title.isHittable {
            let f = title.frame
            XCTAssertFalse(
                abs(f.minY - listTop) < 4 && cards.contains { $0.maxY <= f.minY },
                "title \(title.identifier) \(f) is pinned to the top of the list (\(listTop)) with cards above it"
            )
            for card in cards {
                XCTAssertFalse(
                    f.intersects(card.insetBy(dx: 1, dy: 1)),
                    "title \(title.identifier) \(f) overlaps card \(card)"
                )
            }
        }
        let shots = ([XCUIScreen.main] + XCUIScreen.screens).map { $0.screenshot() }
        let shot = shots.max { $0.pngRepresentation.count < $1.pngRepresentation.count } ?? app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "history-scrolled"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// With the Duo open, closing History's search with its x reopened it (JC137).
    @MainActor
    func testOpenWideHistorySearchClosesAndStaysClosed() throws {
        let app = XCUIApplication.launchedForTesting(["-sampleWorkouts", "40"])
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(app.descendants(matching: .any)["screen.history"].waitForExistence(timeout: 10))
        app.assertSearchClosesAndStaysClosed()
    }

    /// With the Duo open, the scope bar must not sit on the dashboard cards.
    @MainActor
    func testOpenWideHistoryScopeBarKeepsAGapOverTheCards() throws {
        let app = XCUIApplication.launchedForTesting(["-sampleWorkouts", "40"])
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(app.descendants(matching: .any)["screen.history"].waitForExistence(timeout: 10))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        let scopeBar = app.descendants(matching: .any)["scopeBar"].firstMatch
        XCTAssertTrue(scopeBar.waitForExistence(timeout: 10))
        let card = app.descendants(matching: .any)["history.card.thisWeek"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let fieldGap = scopeBar.frame.minY - field.frame.maxY
        let cardGap = card.frame.minY - scopeBar.frame.maxY
        XCTAssertGreaterThanOrEqual(cardGap, fieldGap - 2, "fieldGap \(fieldGap), cardGap \(cardGap)")
        XCTAssertLessThanOrEqual(cardGap, fieldGap + 24, "fieldGap \(fieldGap), cardGap \(cardGap)")
    }

    /// With the Duo open, a tap on History's content puts the search keyboard away and it stays away.
    @MainActor
    func testOpenWideHistoryTapPutsTheKeyboardAway() throws {
        let app = XCUIApplication.launchedForTesting(["-sampleWorkouts", "40"])
        app.selectTab("tab.history", label: "History")
        XCTAssertTrue(app.descendants(matching: .any)["screen.history"].waitForExistence(timeout: 10))
        app.assertTapOnHistoryContentPutsKeyboardAway()
    }

    /// One audit pass of the open logging cover, with `AccessibilityAuditUITests`' known-issue filter.
    @MainActor
    func testOpenWideLoggingAudit() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        XCTAssertTrue(app.descendants(matching: .any)["cover.exercisePane"].waitForExistence(timeout: 10))
        let context = AccessibilityAuditUITests.Context(behindModal: true, truncatesExerciseNames: true)
        try AccessibilityAuditUITests.audit(app, in: self, for: .all, context)
    }
}
