import Foundation

extension Simctl {
    public static let springBoardBundleID = "com.apple.springboard"

    /// `xcrun simctl launch <udid> com.apple.springboard`: foregrounds SpringBoard, which is Home.
    public static func launchArguments(udid: String, bundleID: String) -> [String] {
        ["simctl", "launch", udid, bundleID]
    }

    public func launch(udid: String, bundleID: String) throws {
        let arguments = Simctl.launchArguments(udid: udid, bundleID: bundleID)
        let output = try runner.run("/usr/bin/xcrun", arguments: arguments)
        guard output.status == 0 else {
            throw DuoError.commandFailed(
                command: "xcrun " + arguments.joined(separator: " "),
                status: output.status,
                stderr: output.stderr
            )
        }
    }
}

public enum Home {
    /// Goes to the Home screen, then proves the device still answers with a lit-panel screenshot.
    /// Without `png` the proof capture goes to a temporary file that is removed again.
    public static func run(
        udid: String,
        png: String? = nil,
        runner: any ProcessRunning = SystemProcessRunner(),
        settle: TimeInterval = 1,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws -> ScreenshotResult {
        try Simctl(runner: runner).launch(udid: udid, bundleID: Simctl.springBoardBundleID)
        sleep(settle)
        let path =
            png
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("duo-home-\(UUID().uuidString).png").path
        defer { if png == nil { try? FileManager.default.removeItem(atPath: path) } }
        return try Screenshot.capture(path: path, udid: udid, selector: .lit, runner: runner)
    }
}
