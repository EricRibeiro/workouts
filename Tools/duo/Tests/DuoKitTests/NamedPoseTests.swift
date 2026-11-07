import Testing

@testable import DuoKit

@Suite struct NamedPoseTests {
    @Test func parsesTheFourNamesOnly() {
        for name in ["closed-portrait", "closed-landscape", "open-wide", "open-tall"] {
            #expect(NamedPose(rawValue: name)?.rawValue == name)
        }
        for bad in ["", "open", "closed", "tall", "Open-Tall", "open-portrait", "half-open-wide", "-h"] {
            #expect(NamedPose(rawValue: bad) == nil)
        }
        #expect(NamedPose.allCases.count == 4)
        #expect(NamedPose.usageList == "closed-portrait|closed-landscape|open-wide|open-tall")
    }

    @Test func mapsEachNameToItsFoldAndOrientation() {
        // open-wide is 951x669 pt (open + portrait); open-tall is 669x951 pt (open + landscape-left).
        let expected: [(NamedPose, String, Pose, TargetOrientation)] = [
            (.closedPortrait, "closed", .closed, .portrait),
            (.closedLandscape, "closed", .closed, .landscapeLeft),
            (.openWide, "open", .open, .portrait),
            (.openTall, "open", .open, .landscapeLeft),
        ]
        for (pose, fold, hinge, orientation) in expected {
            #expect(pose.fold.argument == fold)
            #expect(pose.fold.pose == hinge)
            #expect(pose.orientation == orientation)
        }
    }

    @Test func foldTargetsAgreeWithTheFoldCommandPresets() {
        for pose in NamedPose.allCases {
            #expect(FoldTarget.parse(pose.fold.argument) == pose.fold)
        }
    }

    @Test func closedPosesExpectTheCoverPanelAndOpenOnesTheInner() {
        #expect(NamedPose.closedPortrait.fold.expectedPanel == .outer)
        #expect(NamedPose.closedLandscape.fold.expectedPanel == .outer)
        #expect(NamedPose.openWide.fold.expectedPanel == .inner)
        #expect(NamedPose.openTall.fold.expectedPanel == .inner)
    }
}
