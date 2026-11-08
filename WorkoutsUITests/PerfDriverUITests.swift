import XCTest

/// Drives the screens PLAN 6.4 profiles with `xctrace` (recorded by `scripts/perf-record.sh`). It is out of the normal
/// suites: it skips itself unless `PERF_DRIVER` is set, which `TEST_RUNNER_PERF_DRIVER=1` does.
///
/// The recorder attaches to the app after launch and releases the test with a go file, so the trace holds a few idle
/// seconds and the driven interaction, nothing else (for `detail`, the search that finds the exercise happens before the
/// go file).
///
/// Environment (`TEST_RUNNER_`-prefixed on the xcodebuild side):
/// - `PERF_SCENARIO`: `exercises`, `detail` or `history` (default: all three in turn).
/// - `PERF_GO_FILE`: before the driven part, wait (up to 180 s) for this file; the recorder creates it once it is attached.
/// - `PERF_WORKOUTS`: how many finished workouts to seed (default 600, spread over about two years).
final class PerfDriverUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(env["PERF_DRIVER"] != nil, "Profiling driver: run scripts/perf-record.sh")
    }

    @MainActor
    private func launch() -> XCUIApplication {
        XCUIApplication.launchedForTesting(["-sampleWorkouts", env["PERF_WORKOUTS"] ?? "600"])
    }

    private func beginScenario() {
        // The recorder attaches to the running app, then creates the go file.
        let deadline = Date().addingTimeInterval(180)
        while let path = env["PERF_GO_FILE"], !FileManager.default.fileExists(atPath: path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        Thread.sleep(forTimeInterval: 2)
    }

    private func endScenario() {
        Thread.sleep(forTimeInterval: 1)
    }

    private func wants(_ scenario: String) -> Bool {
        let requested = env["PERF_SCENARIO"] ?? "all"
        return requested == "all" || requested == scenario
    }

    private func flingBothWays(_ list: XCUIElement, passes: Int) {
        for _ in 0..<passes { list.swipeUp(velocity: .fast) }
        Thread.sleep(forTimeInterval: 0.5)
        for _ in 0..<passes { list.swipeDown(velocity: .fast) }
        Thread.sleep(forTimeInterval: 0.5)
    }

    @MainActor
    func testExercisesListScroll() throws {
        try XCTSkipUnless(wants("exercises"))
        let app = launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["tab.exercises"].firstMatch.waitForExistence(timeout: 20))
        beginScenario()
        any["tab.exercises"].firstMatch.tap()
        XCTAssertTrue(any["screen.exercises"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        // About 1,000 rows at ~60 pt: 30 fast flings down, then 30 back.
        flingBothWays(list, passes: 30)
        endScenario()
    }

    @MainActor
    func testExerciseDetailCharts() throws {
        try XCTSkipUnless(wants("detail"))
        let app = launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["tab.exercises"].firstMatch.waitForExistence(timeout: 20))
        // Find Barbell Bench Press first: the search is not what this scenario times.
        any["tab.exercises"].firstMatch.tap()
        XCTAssertTrue(any["screen.exercises"].waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3), !app.buttons["Search"].firstMatch.exists {
            app.collectionViews.firstMatch.swipeDown()
        }
        if !search.waitForExistence(timeout: 3) {
            let button = app.buttons["Search"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { search.tap() }
        search.typeText("Barbell Bench Press\n")
        let row = any.matching(
            NSPredicate(format: "identifier BEGINSWITH 'exercises.row.' AND label BEGINSWITH 'Barbell Bench Press'")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no Barbell Bench Press row")

        beginScenario()
        row.tap()
        let segment = app.segmentedControls["exerciseDetail.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 10))
        // Records, History (about 200 sessions of this lift), then Charts across every metric and range.
        segment.buttons["Records"].tap()
        Thread.sleep(forTimeInterval: 1)
        segment.buttons["History"].tap()
        Thread.sleep(forTimeInterval: 1)
        let scroll = app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app.collectionViews.firstMatch
        flingBothWays(scroll, passes: 8)
        segment.buttons["Charts"].tap()
        XCTAssertTrue(any["exerciseDetail.chart"].waitForExistence(timeout: 10), "no chart")
        Thread.sleep(forTimeInterval: 1)
        let ranges = app.segmentedControls["exerciseDetail.chart.range"]
        for range in ["1M", "6M", "1Y", "All"] where ranges.buttons[range].exists {
            ranges.buttons[range].tap()
            Thread.sleep(forTimeInterval: 1)
            for metric in ["totalReps", "volume", "e1rm"] {
                let chip = app.buttons["exerciseDetail.chart.metric.\(metric)"]
                if chip.exists {
                    chip.tap()
                    Thread.sleep(forTimeInterval: 0.7)
                }
            }
        }
        // Scrub the plot (drag across it), which updates the selection readout on every frame.
        let chart = any["exerciseDetail.chart"].firstMatch
        for _ in 0..<4 {
            chart.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
                .press(
                    forDuration: 0.1,
                    thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
                )
        }
        endScenario()
    }

    @MainActor
    func testHistoryDashboardAndList() throws {
        try XCTSkipUnless(wants("history"))
        let app = launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["tab.history"].firstMatch.waitForExistence(timeout: 20))
        beginScenario()
        any["tab.history"].firstMatch.tap()
        XCTAssertTrue(any["screen.history"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        flingBothWays(list, passes: 30)
        endScenario()
    }
}
