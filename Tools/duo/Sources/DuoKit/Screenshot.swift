import Foundation

/// Which panel a screenshot should capture.
public enum DisplaySelector: String, Sendable, CaseIterable {
    /// Whichever panel is lit right now.
    case lit
    /// The primary (cover) panel: `LCD` on the Duo.
    case outer
    /// The integrated panel that is not primary: `LCD-1` on the Duo.
    case inner

    /// Resolves the selector against the display table, without hardcoding panel names.
    public func resolve(in displays: [Display]) throws -> Display {
        switch self {
        case .lit:
            return try Panels.litPanel(in: displays)
        case .outer:
            let primary = displays.filter { $0.primary == true }
            guard primary.count == 1, let panel = primary.first else {
                throw DuoError.panelNotFound(self, available: displays.map(\.name))
            }
            return panel
        case .inner:
            let others = displays.filter { $0.primary != true && $0.integrated }
            guard others.count == 1, let panel = others.first else {
                throw DuoError.panelNotFound(self, available: displays.map(\.name))
            }
            return panel
        }
    }
}

/// Result of a screenshot: where it went and which panel it shows.
public struct ScreenshotResult: Sendable, Equatable {
    public var path: String
    public var display: Display

    /// `<path> 1398x2034 px (466x678 pt, LCD)`
    public var summary: String {
        let pixels = display.orientedPixelSize.map { "\($0.text) px" } ?? "? px"
        let points = display.orientedPointSize.map { "\($0.text) pt" } ?? "? pt"
        return "\(path) \(pixels) (\(points), \(display.name))"
    }
}

public struct Simctl: Sendable {
    public var runner: any ProcessRunning

    public init(runner: any ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    /// `xcrun simctl io <udid> screenshot --display=<name> <path>`
    public static func screenshotArguments(udid: String, displayName: String, path: String) -> [String] {
        ["simctl", "io", udid, "screenshot", "--display=\(displayName)", path]
    }

    public func screenshot(udid: String, displayName: String, path: String) throws {
        let arguments = Simctl.screenshotArguments(udid: udid, displayName: displayName, path: path)
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

public enum Screenshot {
    /// Panel switches leave both panels dark for a moment; `.lit` waits this many extra tries.
    public static let litRetries = 3
    public static let litRetryInterval: TimeInterval = 0.5

    /// Reads the display table, resolves the panel, captures it. `.lit` retries while no panel is lit.
    public static func capture(
        path: String,
        udid: String,
        selector: DisplaySelector = .lit,
        runner: any ProcessRunning = SystemProcessRunner(),
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws -> ScreenshotResult {
        let devicectl = Devicectl(runner: runner)
        var retries = selector == .lit ? litRetries : 0
        var display: Display
        while true {
            do {
                display = try selector.resolve(in: try devicectl.displays(udid: udid))
                break
            } catch DuoError.litPanelCount(0, _) where retries > 0 {
                retries -= 1
                sleep(litRetryInterval)
            }
        }
        try Simctl(runner: runner).screenshot(udid: udid, displayName: display.name, path: path)
        return ScreenshotResult(path: path, display: display)
    }
}
