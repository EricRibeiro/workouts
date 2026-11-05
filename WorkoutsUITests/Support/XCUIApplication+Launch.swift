import XCTest

extension XCUIApplication {
    /// A fresh app launched with `-uiTesting` (in-memory store, no leftover state) plus `extraArguments`. When `screen` is
    /// given, waits for that `screen.*` identifier and fails the test with a clear message if it never appears.
    @MainActor
    static func launchedForTesting(
        _ extraArguments: [String] = [],
        waitingFor screen: String? = nil,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"] + extraArguments
        app.launch()
        if let screen {
            XCTAssertTrue(
                app.descendants(matching: .any)[screen].waitForExistence(timeout: timeout),
                "\(screen) did not appear within \(Int(timeout)) s of launch",
                file: file,
                line: line
            )
        }
        return app
    }

    /// The `-preview <name>` gallery screen, waiting for `screen` when given.
    @MainActor
    static func launchedPreview(
        _ name: String,
        extraArguments: [String] = [],
        waitingFor screen: String? = nil,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIApplication {
        launchedForTesting(
            ["-preview", name] + extraArguments,
            waitingFor: screen,
            timeout: timeout,
            file: file,
            line: line
        )
    }

    /// The sample workout running with its logging cover open (`screen.activeWorkout`), the starting point of every
    /// logging flow. `extraArguments` go between the standard ones (e.g. `-sampleRestSeconds 3`).
    @MainActor
    static func launchedInActiveWorkout(
        _ extraArguments: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIApplication {
        launchedForTesting(
            ["-startSampleWorkout"] + extraArguments + ["-openWorkoutCover"],
            waitingFor: "screen.activeWorkout",
            timeout: 15,
            file: file,
            line: line
        )
    }
}
