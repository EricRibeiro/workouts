import XCTest

/// Prints the accessibility tree of a `-preview <Name>` gallery screen (PLAN device-tool C.6): `./dev tree <Name>` runs it
/// with `TEST_RUNNER_TREE_PREVIEW=<Name>` and prints the text. Out of the normal suites: it skips itself unless `TREE_PREVIEW`
/// is set, so the full `./dev ui-test` only counts one more skipped test.
final class TreeDumpUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDump() throws {
        let name = ProcessInfo.processInfo.environment["TREE_PREVIEW"] ?? ""
        try XCTSkipIf(name.isEmpty, "Tree dump: run with ./dev tree <PreviewName>")

        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-preview", name]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        // The first query makes XCUITest wait for the app to be idle before it snapshots the hierarchy.
        _ = app.descendants(matching: .any).firstMatch.waitForExistence(timeout: 10)

        let tree = app.debugDescription
        let attachment = XCTAttachment(string: tree)
        attachment.name = "tree-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("=== TREE BEGIN ===\n\(tree)\n=== TREE END ===")
    }
}
