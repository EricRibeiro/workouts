import Foundation
import Testing

@testable import DuoKit

private final class HomeRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var launchStatus: Int32 = 0

    var calls: [[String]] { lock.withLock { recorded } }

    func run(_ executable: String, arguments: [String]) throws -> ProcessOutput {
        lock.withLock { recorded.append(arguments) }
        switch arguments.first {
        case "devicectl":
            let url = try #require(
                Bundle.module.url(forResource: "displays-closed", withExtension: "json", subdirectory: "Fixtures")
            )
            return ProcessOutput(status: 0, stdout: try Data(contentsOf: url), stderr: "")
        case "simctl" where arguments.dropFirst().first == "launch":
            return ProcessOutput(status: launchStatus, stdout: Data(), stderr: launchStatus == 0 ? "" : "not booted")
        default:
            return ProcessOutput(status: 0, stdout: Data(), stderr: "")
        }
    }
}

@Suite struct HomeTests {
    @Test func launchArgumentsTargetSpringBoard() {
        #expect(
            Simctl.launchArguments(udid: "U", bundleID: Simctl.springBoardBundleID)
                == ["simctl", "launch", "U", "com.apple.springboard"]
        )
    }

    @Test func launchesThenCapturesTheLitPanel() throws {
        let runner = HomeRunner()
        var slept: [TimeInterval] = []
        let result = try Home.run(udid: "U", png: "/tmp/h.png", runner: runner, sleep: { slept.append($0) })
        #expect(result.summary == "/tmp/h.png 1398x2034 px (466x678 pt, LCD)")
        #expect(runner.calls.first == ["simctl", "launch", "U", "com.apple.springboard"])
        #expect(runner.calls.last == ["simctl", "io", "U", "screenshot", "--display=LCD", "/tmp/h.png"])
        #expect(slept == [1])
    }

    @Test func withoutAPNGItCapturesToATemporaryFile() throws {
        let runner = HomeRunner()
        _ = try Home.run(udid: "U", runner: runner, sleep: { _ in })
        let shot = try #require(runner.calls.last?.last)
        #expect(shot.contains("duo-home-"))
        #expect(!FileManager.default.fileExists(atPath: shot))
    }

    @Test func aFailedLaunchStopsBeforeTheScreenshot() {
        let runner = HomeRunner()
        runner.launchStatus = 149
        do {
            _ = try Home.run(udid: "U", runner: runner, sleep: { _ in })
            Issue.record("expected a failure")
        } catch {
            #expect("\(error)".contains("exit status 149: not booted"))
        }
        #expect(runner.calls.count == 1)
    }
}
