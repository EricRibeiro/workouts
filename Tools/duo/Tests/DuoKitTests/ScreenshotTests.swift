import Foundation
import Testing

@testable import DuoKit

/// Serves the closed-Duo fixture for `devicectl` and records every call.
private final class RecordingRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    let simctlStatus: Int32

    init(simctlStatus: Int32 = 0) {
        self.simctlStatus = simctlStatus
    }

    var calls: [[String]] { lock.withLock { recorded } }

    func run(_ executable: String, arguments: [String]) throws -> ProcessOutput {
        lock.withLock { recorded.append(arguments) }
        if arguments.first == "devicectl" {
            let url = try #require(
                Bundle.module.url(forResource: "displays-closed", withExtension: "json", subdirectory: "Fixtures")
            )
            return ProcessOutput(status: 0, stdout: try Data(contentsOf: url), stderr: "")
        }
        return ProcessOutput(status: simctlStatus, stdout: Data(), stderr: simctlStatus == 0 ? "" : "boom")
    }
}

private func closedDuo() throws -> [Display] {
    let url = try #require(
        Bundle.module.url(forResource: "displays-closed", withExtension: "json", subdirectory: "Fixtures")
    )
    return try Devicectl.decodeDisplays(Data(contentsOf: url))
}

@Suite struct DisplaySelectorTests {
    @Test func litPicksTheOuterPanelOnAClosedDuo() throws {
        #expect(try DisplaySelector.lit.resolve(in: closedDuo()).name == "LCD")
    }

    @Test func outerIsThePrimaryPanel() throws {
        #expect(try DisplaySelector.outer.resolve(in: closedDuo()).name == "LCD")
    }

    @Test func innerIsTheNonPrimaryIntegratedPanel() throws {
        #expect(try DisplaySelector.inner.resolve(in: closedDuo()).name == "LCD-1")
    }

    @Test func innerFailsWhenThereIsOnlyOnePanel() {
        let single = [Display(name: "Main", primary: true, integrated: true)]
        #expect(throws: DuoError.panelNotFound(.inner, available: ["Main"])) {
            try DisplaySelector.inner.resolve(in: single)
        }
    }

    @Test func outerFailsWithoutAPrimary() {
        #expect(throws: DuoError.panelNotFound(.outer, available: [])) {
            try DisplaySelector.outer.resolve(in: [])
        }
    }
}

@Suite struct OrientedSizeTests {
    private func panel(current: String?, native: String?) -> Display {
        Display(
            name: "P",
            nativeSize: [2007, 2853],
            pointScale: 3,
            currentOrientation: current,
            nativeOrientation: native
        )
    }

    @Test func quarterTurnsSwapWidthAndHeight() {
        for current in ["rot90", "rot270"] {
            let turned = panel(current: current, native: "rot0")
            #expect(turned.isQuarterTurned)
            #expect(turned.orientedPixelSize == Size(width: 2853, height: 2007))
            #expect(turned.orientedPointSize == Size(width: 951, height: 669))
        }
    }

    @Test func matchingOrHalfTurnedKeepsTheNativeSize() {
        for current in ["rot0", "rot180", nil] {
            #expect(!panel(current: current, native: "rot0").isQuarterTurned)
            #expect(panel(current: current, native: "rot0").orientedPixelSize == Size(width: 2007, height: 2853))
        }
        #expect(!panel(current: "rot90", native: "rot90").isQuarterTurned)
        #expect(panel(current: "rot0", native: "rot90").isQuarterTurned)
    }
}

@Suite struct ScreenshotTests {
    @Test func argumentsTargetTheDisplayByName() {
        #expect(
            Simctl.screenshotArguments(udid: "U", displayName: "LCD-1", path: "/tmp/a.png")
                == ["simctl", "io", "U", "screenshot", "--display=LCD-1", "/tmp/a.png"]
        )
    }

    @Test func defaultCaptureUsesTheLitPanel() throws {
        let runner = RecordingRunner()
        let result = try Screenshot.capture(path: "/tmp/a.png", udid: "U", runner: runner)
        #expect(result.summary == "/tmp/a.png 1398x2034 px (466x678 pt, LCD)")
        #expect(runner.calls.last == ["simctl", "io", "U", "screenshot", "--display=LCD", "/tmp/a.png"])
        #expect(runner.calls.count == 2)
    }

    @Test func innerCaptureNamesTheInnerPanel() throws {
        let runner = RecordingRunner()
        let result = try Screenshot.capture(path: "/tmp/b.png", udid: "U", selector: .inner, runner: runner)
        #expect(result.summary == "/tmp/b.png 2853x2007 px (951x669 pt, LCD-1)")
        #expect(runner.calls.last == ["simctl", "io", "U", "screenshot", "--display=LCD-1", "/tmp/b.png"])
    }

    @Test func simctlFailureIsReported() {
        let runner = RecordingRunner(simctlStatus: 3)
        do {
            _ = try Screenshot.capture(path: "/tmp/a.png", udid: "U", runner: runner)
            Issue.record("expected a failure")
        } catch {
            #expect("\(error)".contains("exit status 3: boom"))
        }
    }
}
