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
        app.launchArguments += ["-uiTesting"] + withDefaultEnvironment(extraArguments)
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

    /// `arguments` plus the pinned environment: Large text, so a run never depends on what a pool simulator was left at.
    /// A caller's own `-UIPreferredContentSizeCategoryName` wins. The app is dark-only (`UIUserInterfaceStyle`), so no style is pinned.
    static func withDefaultEnvironment(_ arguments: [String]) -> [String] {
        var result = arguments
        if !arguments.contains("-UIPreferredContentSizeCategoryName") {
            result += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        }
        return result
    }

    /// Expires the running rest at once through the app's Debug seam (`RestExpirySeam`): the ring/label then go through the
    /// real "over" state and the 3 s grace, without the test waiting on a countdown. Start the rest, assert it runs, then call this.
    func expireRestNow() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.ericribeiro.Workouts.debug.expireRest" as CFString),
            nil,
            nil,
            true
        )
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
