import Foundation

/// The four layouts the Duo is checked in (names match `verify-ui` and PLAN Phase 6), each one a hinge fold plus an
/// orientation. The names describe the layout, not the device rotation: `open-wide` (951x669 pt) is the open
/// hinge in portrait and `open-tall` (669x951 pt) is the open hinge in landscape-left.
public enum NamedPose: String, Sendable, CaseIterable {
    case closedPortrait = "closed-portrait"
    case closedLandscape = "closed-landscape"
    case openWide = "open-wide"
    case openTall = "open-tall"

    /// The hinge target; `closed` and `open` are presets, so parsing cannot fail.
    public var fold: FoldTarget {
        switch self {
        case .closedPortrait, .closedLandscape: FoldTarget(argument: "closed", angle: 0, pose: .closed)
        case .openWide, .openTall: FoldTarget(argument: "open", angle: 180, pose: .open)
        }
    }

    public var orientation: TargetOrientation {
        switch self {
        case .closedPortrait, .openWide: .portrait
        case .closedLandscape, .openTall: .landscapeLeft
        }
    }

    /// The names accepted on the command line, for usage text.
    public static var usageList: String { allCases.map(\.rawValue).joined(separator: "|") }
}

public struct PoseResult: Sendable, Equatable {
    public var pose: NamedPose
    public var fold: FoldResult
    public var orient: OrientResult

    /// `pose open-tall: hinge 180 deg (open), lit panel LCD-1, device landscapeLeft, lit panel LCD-1 rot0`,
    /// then the PNG line when one was taken.
    public var summary: String {
        let angle = fold.reading.angleDegrees
        let angleText = angle == angle.rounded() ? String(Int(angle)) : String(angle)
        let line =
            "pose \(pose.rawValue): hinge \(angleText) deg (\(fold.reading.pose.rawValue)), "
            + "lit panel \(fold.litPanel), \(orient.observation.text)"
        guard let screenshot = orient.screenshot else { return line }
        return line + "\n" + screenshot.summary
    }
}

public enum PoseCommand {
    /// Folds, then rotates (the orientation check reads the panel the fold lit), each verified by the existing
    /// `Fold` / `Orient` reads; the optional PNG is taken last, once, from the lit panel.
    public static func run(
        pose: NamedPose,
        udid: String,
        guestPath: String,
        png: String? = nil,
        runner: any ProcessRunning = SystemProcessRunner(),
        now: () -> Date = Date.init,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws -> PoseResult {
        let folded = try Fold.run(
            target: pose.fold,
            udid: udid,
            guestPath: guestPath,
            runner: runner,
            now: now,
            sleep: sleep
        )
        let oriented = try Orient.run(
            target: pose.orientation,
            udid: udid,
            guestPath: guestPath,
            png: png,
            runner: runner,
            sleep: sleep
        )
        return PoseResult(pose: pose, fold: folded, orient: oriented)
    }
}
