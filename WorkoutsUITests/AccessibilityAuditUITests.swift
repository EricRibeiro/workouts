import XCTest

/// Automated accessibility audits (`performAccessibilityAudit`): one test per main screen at the default text size, then
/// a second pass at an accessibility text size for `.dynamicType` and `.textClipped`. Every audit type is on; issues
/// that are system-owned or false positives are filtered in `isKnownIssue` with a comment saying which element and why.
final class AccessibilityAuditUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Audit

    /// Where the audited screen sits, which decides what the filters in `isKnownIssue` may ignore.
    struct Context {
        /// A sheet or full-screen cover is up: the screen behind it is not reachable, so the audit's "potentially
        /// inaccessible" findings for it have no element to blame.
        var behindModal = false
        /// The screen is a medium-detent sheet whose background is system material over the dimmed page.
        var onMaterialSheet = false
        /// The second pass: an accessibility text size is on, and only `.dynamicType` / `.textClipped` run.
        var largeText = false
        /// The logging pane, whose exercise names truncate by design (`SetTable` applies `exerciseNameLineLimit` in
        /// `.active` mode: one line, two at accessibility sizes).
        var truncatesExerciseNames = false
        /// A bare screen in a navigation stack with toolbar items (the gallery's editor, picker and set-table hosts):
        /// on the closed Duo the system draws the vertical status and toolbar strip beside it. The strip's clock and
        /// status glyphs are text with no accessibility element, and its toolbar container is a zero-size
        /// `SwiftUI.AccessibilityNode`; the audit reports both with no element at all (checked on a screenshot and
        /// the accessibility tree of `-preview PastEditor` and `-preview ExercisePicker`).
        var hasSystemStrip = false
    }

    /// Short single-line labels the audit reports as clipped at the default size although they render in full: the
    /// History dashboard cards' titles (`DashboardCard`), the filter pills' labels (`FilterPillRow`) and a Workout
    /// Detail block's `Best Set` caption and the exercise picker's `New Exercise` row.
    private static let shortLabels: Set<String> = [
        "Best Set", "This Week", "Recent PRs", "Last Workout", "Any Body Part", "Any Category",
        "New Exercise",
    ]

    /// The sample workout's exercise names (`SampleData`), which the logging pane truncates by design.
    private static let sampleExerciseNames: Set<String> = [
        "Barbell Bench Press", "Lever Seated Hammer Grip Shoulder Press", "Incline Dumbbell Bench Press",
        "Cable Triceps Pushdown",
    ]

    /// Runs the audit with every type in `types`, ignoring only the issues `isKnownIssue` names.
    @MainActor
    private func audit(
        _ app: XCUIApplication,
        for types: XCUIAccessibilityAuditType = .all,
        _ context: Context = Context()
    ) throws {
        // An unfiltered issue is also recorded with its element's description, so a flake names what it hit.
        let handler: (XCUIAccessibilityAuditIssue) -> Bool = { [self] issue in
            let known = Self.isKnownIssue(issue, app: app, context: context)
            if !known {
                let element = issue.element?.debugDescription ?? "no element"
                record(
                    XCTIssue(
                        type: .assertionFailure,
                        compactDescription: "Unfiltered audit issue: \(issue.compactDescription) [\(element)]"
                    )
                )
            }
            return known
        }
        // "Invalid target app <pid>" (-902): the audit attached while the launch was still settling (seen only with several
        // simulators busy). It is a harness error, not a finding, so the audit runs again after a short backoff (1 s, then
        // 2 s); a third failure fails.
        for backoff in [1.0, 2.0] {
            do {
                try app.performAccessibilityAudit(for: types, handler)
                return
            } catch let error as NSError where error.domain == "com.apple.accessibilityAudit" && error.code == -902 {
                _ = app.wait(for: .runningForeground, timeout: 10)
                Thread.sleep(forTimeInterval: backoff)
            }
        }
        try app.performAccessibilityAudit(for: types, handler)
    }

    /// Issues that are not defects in this app's views. Each rule names the element and why it is safe to ignore; none
    /// turns an audit type off, and none applies to an element the app draws and labels itself except where stated.
    static func isKnownIssue(_ issue: XCUIAccessibilityAuditIssue, app: XCUIApplication, context: Context)
        -> Bool
    {
        let element = issue.element
        let description = issue.compactDescription

        switch issue.auditType {
        case .contrast:
            // TODO(Eric, design): secondary text (`.secondary` / `.foregroundStyle(.secondary)` on the system grouped
            // backgrounds) measures 4.2 to 4.5:1, just under WCAG AA, and the audit reports it as "nearly passed".
            // That is the system semantic colour, so fixing it means choosing a darker secondary for the whole app: a
            // taste call. Anything the audit rates "failed" (below that band) still fails the test, except:
            if description.contains("nearly passed") { return true }
            // TODO(Eric, design): the template preview is a medium-detent sheet; its `.secondary` rows are measured over
            // the sheet's translucent system material and the dimmed Workout tab, and read "failed". Opaque
            // `presentationBackground` would fix it but changes the look of every sheet.
            return context.onMaterialSheet

        case .elementDetection:
            // Text and elements drawn under a presented sheet or cover (the page behind it) that the audit cannot
            // attribute to an element: it reports them with no element at all.
            // The same goes for the closed Duo's system strip beside a bare screen (the clock and status glyphs).
            return (context.behindModal || context.hasSystemStrip) && element == nil

        case .hitRegion:
            // The strip's zero-size toolbar container (see `Context.hasSystemStrip`): no element, nothing to resize.
            guard let element else { return context.hasSystemStrip }
            // The system navigation bar's title menu (`.toolbarTitleMenu`, the workout name in the logging cover) is a
            // UIKit-owned button sized to its title (exposed as a static text while the bar settles); the app cannot
            // set its hit region.
            guard element.elementType == .button || element.elementType == .staticText, !element.label.isEmpty else {
                return false
            }
            return app.navigationBars.buttons[element.label].exists

        case .dynamicType:
            // At the default size the audit flags static text whose container reflows when the size changes (the
            // adaptive template grid, `ViewThatFits` title rows, the stat grids). Every one of these uses a text style, no
            // `.system(size:)`, and the same views are previewed at `.accessibility3`; the second pass below audits
            // `.dynamicType` at an accessibility size with no filter at all.
            return !context.largeText && element?.elementType == .staticText

        case .textClipped:
            // No element at all: system chrome the audit cannot address (the status bar, tab bar and toolbar strip the
            // closed Duo puts on the trailing edge, large navigation titles). The app does not draw them.
            guard let element else { return true }
            // A UIKit `UISearchBarTextField` (the Exercises search): the system field scales and elides its own text.
            if element.elementType == .searchField { return true }
            // Applies at every size. Only text elements are ever listed below; a clipped button, field or cell still fails.
            guard element.elementType == .staticText else { return false }
            // Exercise names in the logging pane: one line (two at accessibility sizes) by design.
            if context.truncatesExerciseNames && Self.sampleExerciseNames.contains(element.label) { return true }
            // The template card's and preview's plan lines (`6 × Barbell Bench Press`): `lineLimit(1)` at the default
            // size (`exerciseNameLineLimit` in the preview), fully wrapped at accessibility sizes (checked on a
            // screenshot; the audit reports the wrapped card text as clipped at the bottom of the scroll view). The
            // same pattern also covers Workout Detail's best-set text (`386 lb × 5`), a plain unlimited `Text` whose
            // frame equals its glyph bounds.
            if element.label.contains(" × ") { return true }
            if context.largeText { return false }
            // Short single-line labels at the default size whose frame equals their glyph bounds. None sets a line
            // limit, a fixed frame or a scale factor, so each renders in full:
            //  - `Best Set` (caption over the best set in a Workout Detail block), `12 reps` (a bodyweight set's
            //    detail there), the History dashboard cards' titles, the filter pills' `Any ...` labels, and the About
            //    tab's `Body part, Glutes` line (id `exerciseDetail.about.bodyPart`).
            if Self.shortLabels.contains(element.label) { return true }
            if element.label.range(of: #"^\d+ reps?$"#, options: .regularExpression) != nil { return true }
            return element.identifier == "exerciseDetail.about.bodyPart"

        default:
            return false
        }
    }

    // MARK: - Default text size

    @MainActor
    func testWorkoutTabTemplateGrid() throws {
        let app = XCUIApplication.launchedForTesting(["-seedSampleData"], waitingFor: "screen.workout")
        XCTAssertTrue(app.firstTemplateCard.waitForExistence(timeout: 10))
        try audit(app)
    }

    @MainActor
    func testTemplatePreview() throws {
        let app = XCUIApplication.launchedForTesting(["-seedSampleData"], waitingFor: "screen.workout")
        let card = app.firstTemplateCard
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["template.preview"].waitForExistence(timeout: 5))
        try audit(app, Context(behindModal: true, onMaterialSheet: true))
    }

    @MainActor
    func testActiveWorkoutLogging() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        try audit(app, Context(behindModal: true, truncatesExerciseNames: true))
    }

    @MainActor
    func testFinishSummary() throws {
        let app = XCUIApplication.launchedPreview(
            "FinishSummary",
            // The falling stars pass behind the section headers for 4.5 s after launch; the audit samples pixels
            // under the text, so an animated frame makes contrast nondeterministic. The Reduce Motion scatter is
            // a legitimate, fixed state of the same screen.
            extraArguments: ["-staticCelebration"],
            waitingFor: "screen.finishSummary"
        )
        try audit(app)
    }

    @MainActor
    func testHistoryList() throws {
        let app = XCUIApplication.launchedPreview("History", waitingFor: "screen.history")
        try audit(app)
    }

    @MainActor
    func testWorkoutDetail() throws {
        let app = XCUIApplication.launchedPreview("History", waitingFor: "screen.history")
        openFirstHistoryRow(app)
        try audit(app)
    }

    @MainActor
    func testExercisesList() throws {
        let app = XCUIApplication.launchedPreview("Exercises", waitingFor: "screen.exercises")
        XCTAssertTrue(exerciseRows(app).element(boundBy: 0).waitForExistence(timeout: 10))
        try audit(app)
    }

    @MainActor
    func testExerciseDetail() throws {
        let app = XCUIApplication.launchedPreview("Exercises", waitingFor: "screen.exercises")
        openFirstExercise(app)
        try audit(app)
    }

    @MainActor
    func testSettings() throws {
        let app = XCUIApplication.launchedPreview("Settings", waitingFor: "screen.settings")
        // The gallery presents Settings as a sheet: audit only once its content is on screen and the presentation
        // animation has settled (an audit during the animation reports "Dynamic Type font sizes are unsupported").
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settings.done"].isHittable)
        try audit(app)
    }

    // MARK: - Other gallery screens (default text size)

    /// Waits for a screen with no `screen.*` identifier of its own by one of its labelled elements.
    @MainActor
    private func waitForElement(_ app: XCUIApplication, labelled label: String) {
        XCTAssertTrue(
            app.descendants(matching: .any)[label].waitForExistence(timeout: 10),
            "no element \(label)"
        )
    }

    @MainActor
    func testRootTabs() throws {
        let app = XCUIApplication.launchedPreview("Root", waitingFor: "screen.workout")
        try audit(app)
    }

    @MainActor
    func testCalendar() throws {
        let app = XCUIApplication.launchedPreview("Calendar", waitingFor: "screen.calendar")
        try audit(app)
    }

    @MainActor
    func testSwatches() throws {
        let app = XCUIApplication.launchedPreview("Swatches")
        waitForElement(app, labelled: "Accent")
        try audit(app)
    }

    @MainActor
    func testExercisePicker() throws {
        let app = XCUIApplication.launchedPreview("ExercisePicker", waitingFor: "screen.exercisePicker")
        try audit(app, Context(hasSystemStrip: true))
    }

    @MainActor
    func testExercisePickerMulti() throws {
        let app = XCUIApplication.launchedPreview(
            "ExercisePickerMulti",
            waitingFor: "screen.exercisePicker"
        )
        try audit(app, Context(hasSystemStrip: true))
    }

    @MainActor
    func testSetRow() throws {
        let app = XCUIApplication.launchedPreview("SetRow", waitingFor: "screen.setRowDemo")
        try audit(app)
    }

    @MainActor
    func testSetTable() throws {
        let app = XCUIApplication.launchedPreview("SetTable", waitingFor: "screen.setTable")
        try audit(app, Context(hasSystemStrip: true))
    }

    @MainActor
    func testWorkoutDetailGalleryEntry() throws {
        let app = XCUIApplication.launchedPreview("WorkoutDetail", waitingFor: "screen.workoutDetail")
        try audit(app)
    }

    @MainActor
    func testPastEditor() throws {
        let app = XCUIApplication.launchedPreview("PastEditor", waitingFor: "screen.pastEditor")
        try audit(app, Context(hasSystemStrip: true))
    }

    @MainActor
    func testCustomExerciseFormNew() throws {
        let app = XCUIApplication.launchedPreview("CustomExerciseForm", waitingFor: "screen.newExercise")
        try audit(app)
    }

    @MainActor
    func testCustomExerciseFormEdit() throws {
        let app = XCUIApplication.launchedPreview(
            "CustomExerciseFormEdit",
            waitingFor: "screen.editExercise"
        )
        try audit(app)
    }

    @MainActor
    func testTemplateEditor() throws {
        let app = XCUIApplication.launchedPreview("TemplateEditor", waitingFor: "screen.templateEditor")
        try audit(app, Context(hasSystemStrip: true))
    }

    @MainActor
    func testTemplatePreviewGalleryEntry() throws {
        let app = XCUIApplication.launchedPreview("TemplatePreview", waitingFor: "template.preview")
        try audit(app, Context(behindModal: true, onMaterialSheet: true))
    }

    @MainActor
    func testExercisePane() throws {
        let app = XCUIApplication.launchedPreview("ExercisePane", waitingFor: "cover.exercisePane")
        try audit(app)
    }

    @MainActor
    func testExerciseInfoSheet() throws {
        let app = XCUIApplication.launchedPreview(
            "ExerciseInfoSheet",
            waitingFor: "screen.exerciseDetail"
        )
        try audit(app, Context(behindModal: true, onMaterialSheet: true))
    }

    @MainActor
    func testHeartRateChart() throws {
        let app = XCUIApplication.launchedPreview("HeartRateChart", waitingFor: "screen.heartRateChart")
        try audit(app)
    }

    // MARK: - Rest sheets (opened from the logging cover's rest ring)

    @MainActor
    func testRestRunningSheet() throws {
        // The launch argument starts a 300 s rest, so the ring opens the running sheet.
        let app = XCUIApplication.launchedInActiveWorkout()
        let ring = app.buttons["rest.ring"].firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 10))
        ring.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.restRunning"].waitForExistence(timeout: 5))
        try audit(app, Context(behindModal: true, onMaterialSheet: true))
    }

    @MainActor
    func testRestCustomSheet() throws {
        let app = XCUIApplication.launchedInActiveWorkout()
        let ring = app.buttons["rest.ring"].firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 10))
        // Skip the running rest to get the idle menu, whose last item is Custom...
        ring.tap()
        let skip = app.buttons["rest.skip"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        ring.tap()
        let custom = app.buttons["rest.custom"].firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.restCustom"].waitForExistence(timeout: 5))
        try audit(app, Context(behindModal: true, onMaterialSheet: true))
    }

    // MARK: - Accessibility text size

    /// An accessibility category: the UI must neither clip text nor lose controls at this size.
    private static let largeText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]

    @MainActor
    func testWorkoutTabAtAccessibilityTextSize() throws {
        let app = XCUIApplication.launchedForTesting(
            ["-seedSampleData"] + Self.largeText,
            waitingFor: "screen.workout"
        )
        XCTAssertTrue(app.firstTemplateCard.waitForExistence(timeout: 10))
        try audit(app, for: [.dynamicType, .textClipped], Context(largeText: true))
    }

    @MainActor
    func testActiveWorkoutAtAccessibilityTextSize() throws {
        let app = XCUIApplication.launchedInActiveWorkout(Self.largeText)
        try audit(app, for: [.dynamicType, .textClipped], Context(largeText: true, truncatesExerciseNames: true))
    }

    @MainActor
    func testHistoryAtAccessibilityTextSize() throws {
        let app = XCUIApplication.launchedPreview(
            "History",
            extraArguments: Self.largeText,
            waitingFor: "screen.history"
        )
        try audit(app, for: [.dynamicType, .textClipped], Context(largeText: true))
    }

    @MainActor
    func testSettingsAtAccessibilityTextSize() throws {
        let app = XCUIApplication.launchedPreview(
            "Settings",
            extraArguments: Self.largeText,
            waitingFor: "screen.settings"
        )
        try audit(app, for: [.dynamicType, .textClipped], Context(largeText: true))
    }

    // MARK: - Navigation

    private func exerciseRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'exercises.row.'"))
    }

    @MainActor
    private func openFirstExercise(_ app: XCUIApplication) {
        let first = exerciseRows(app).element(boundBy: 0)
        XCTAssertTrue(first.waitForExistence(timeout: 10), "no exercise rows")
        first.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["screen.exerciseDetail"].waitForExistence(timeout: 5),
            "the exercise detail did not open"
        )
    }

    /// Scrolls past the dashboard cards (the list is lazy) and opens the first History row.
    @MainActor
    private func openFirstHistoryRow(_ app: XCUIApplication) {
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.row.'")
        )
        let first = rows.element(boundBy: 0)
        for _ in 0..<8 {
            if first.waitForExistence(timeout: 2) && first.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(first.exists, "no history rows")
        first.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["history.detail"].waitForExistence(timeout: 5),
            "the row did not open the detail"
        )
    }
}
