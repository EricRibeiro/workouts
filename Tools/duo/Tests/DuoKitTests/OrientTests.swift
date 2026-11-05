import Foundation
import Testing

@testable import DuoKit

private let outer = Display(name: "LCD", primary: true, integrated: true)
private let inner = Display(name: "LCD-1", primary: false, integrated: true)

private func lit(_ display: Display, _ rotation: String) -> Display {
    var copy = display
    copy.backlightState = "activeOn"
    copy.currentOrientation = rotation
    return copy
}

private func observation(_ device: String, _ panel: Display?) -> OrientationObservation {
    OrientationObservation(deviceOrientation: device, litPanel: panel)
}

@Suite struct TargetOrientationTests {
    @Test func expectedRotationsMatchTheMeasuredDuo() {
        // Measured on iPhone Duo 3, iOS 27.2: cover panel, then inner panel.
        #expect(TargetOrientation.portrait.expectedRotation(of: outer) == "rot0")
        #expect(TargetOrientation.landscapeLeft.expectedRotation(of: outer) == "rot270")
        #expect(TargetOrientation.landscapeRight.expectedRotation(of: outer) == "rot90")
        #expect(TargetOrientation.portrait.expectedRotation(of: inner) == "rot90")
        #expect(TargetOrientation.landscapeLeft.expectedRotation(of: inner) == "rot0")
        #expect(TargetOrientation.landscapeRight.expectedRotation(of: inner) == "rot180")
    }

    @Test func namesFollowDevicectl() {
        #expect(TargetOrientation(rawValue: "landscape-left")?.deviceName == "landscapeLeft")
        #expect(TargetOrientation(rawValue: "portrait-upside-down") == nil)
    }
}

@Suite struct OrientationObservationTests {
    @Test func needsDeviceAndLitPanelToAgree() {
        #expect(observation("landscapeLeft", lit(outer, "rot270")).matches(.landscapeLeft))
        #expect(!observation("portrait", lit(outer, "rot270")).matches(.landscapeLeft))
        #expect(!observation("landscapeLeft", lit(outer, "rot0")).matches(.landscapeLeft))
        #expect(!observation("landscapeLeft", nil).matches(.landscapeLeft))
        #expect(observation("portrait", lit(inner, "rot90")).matches(.portrait))
        #expect(!observation("portrait", lit(inner, "rot0")).matches(.portrait))
    }

    @Test func textDescribesWhatWasSeen() {
        #expect(observation("portrait", lit(outer, "rot0")).text == "device portrait, lit panel LCD rot0")
        #expect(observation("portrait", nil).text == "device portrait, lit panel none ?")
    }
}

@Suite struct OrientationVerifierTests {
    @Test func reachedOnTheFirstPollWithoutSleeping() throws {
        var sleeps: [TimeInterval] = []
        let result = try OrientationVerifier.verify(
            target: .portrait,
            observe: { observation("portrait", lit(outer, "rot0")) },
            sleep: { sleeps.append($0) }
        )
        #expect(result.reached)
        #expect(result.polls == 1)
        #expect(sleeps.isEmpty)
    }

    @Test func waitsForTheSlowerOfTheTwoReads() throws {
        var script = [
            observation("portrait", lit(outer, "rot270")),  // panel turned, device not yet
            observation("landscapeLeft", lit(outer, "rot0")),  // device turned, panel not yet
            observation("landscapeLeft", nil),  // panel dark mid-transition
            observation("landscapeLeft", lit(outer, "rot270")),
        ]
        var sleeps: [TimeInterval] = []
        let result = try OrientationVerifier.verify(
            target: .landscapeLeft,
            observe: { script.removeFirst() },
            sleep: { sleeps.append($0) }
        )
        #expect(result.reached)
        #expect(result.polls == 4)
        #expect(sleeps == [0.5, 0.5, 0.5])
    }

    @Test func failsAfterTheAttemptsAndKeepsTheLastObservation() throws {
        let stuck = observation("portrait", lit(outer, "rot0"))
        var sleeps = 0
        let result = try OrientationVerifier.verify(
            target: .landscapeRight,
            attempts: 5,
            observe: { stuck },
            sleep: { _ in sleeps += 1 }
        )
        #expect(!result.reached)
        #expect(result.polls == 5)
        #expect(result.last == stuck)
        #expect(sleeps == 4)
    }

    @Test func aThrowingReadAborts() {
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try OrientationVerifier.verify(target: .portrait, observe: { throw Boom() }, sleep: { _ in })
        }
    }
}

@Suite struct OrientCommandTests {
    @Test func decodesDeviceOrientation() throws {
        let json = #"{"info":{},"result":{"deviceOrientation":"landscapeLeft","deviceOrientationNonFlat":"x"}}"#
        #expect(try Devicectl.decodeDeviceOrientation(Data(json.utf8)) == "landscapeLeft")
        #expect(throws: DuoError.self) { try Devicectl.decodeDeviceOrientation(Data("{}".utf8)) }
    }

    @Test func rotateArguments() {
        #expect(
            Simctl.rotateArguments(udid: "U", guestPath: "/g", orientation: .landscapeRight)
                == ["simctl", "spawn", "U", "/g", "rotate", "landscape-right"]
        )
    }
}
