import Foundation
import Testing

@testable import DuoKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private struct FakeRunner: ProcessRunning {
    var output: ProcessOutput

    func run(_ executable: String, arguments: [String]) throws -> ProcessOutput { output }
}

@Suite struct DevicectlTests {
    @Test func decodesTheClosedDuoFixture() throws {
        let displays = try Devicectl.decodeDisplays(fixture("displays-closed"))
        #expect(displays.count == 2)
        let outer = displays[0]
        #expect(outer.name == "LCD")
        #expect(outer.displayId == 1)
        #expect(outer.uniqueId == "3B3FFF5B-410A-4BD8-80CA-1885594903B2")
        #expect(outer.active == true)
        #expect(outer.backlightState == "activeOn")
        #expect(outer.nativeSize == [1398, 2034])
        #expect(outer.pointScale == 3)
        #expect(outer.currentOrientation == "rot0")
        #expect(outer.primary == true)
        #expect(outer.integrated)
        let inner = displays[1]
        #expect(inner.name == "LCD-1")
        #expect(inner.active == false)
        #expect(inner.backlightState == "off")
        #expect(inner.nativeSize == [2007, 2853])
        #expect(inner.primary == false)
    }

    @Test func toleratesMissingOptionalFields() throws {
        let json = #"{"result":{"displays":[{"name":"X","future":1}]}}"#
        let displays = try Devicectl.decodeDisplays(Data(json.utf8))
        #expect(displays == [Display(name: "X")])
        #expect(displays[0].pixelSize == nil)
        #expect(displays[0].pointSize == nil)
        #expect(!displays[0].isLit)
    }

    @Test func reportsGarbageAsUndecodable() {
        #expect(throws: DuoError.self) { try Devicectl.decodeDisplays(Data("not json".utf8)) }
    }

    @Test func displaysGoesThroughTheRunner() throws {
        let ok = ProcessOutput(status: 0, stdout: try fixture("displays-closed"), stderr: "")
        let displays = try Devicectl(runner: FakeRunner(output: ok)).displays(udid: "U")
        #expect(displays.map(\.name) == ["LCD", "LCD-1"])
    }

    @Test func nonZeroExitCarriesStderr() {
        let failed = ProcessOutput(status: 1, stdout: Data(), stderr: "no such device\n")
        do {
            _ = try Devicectl(runner: FakeRunner(output: failed)).displays(udid: "U")
            Issue.record("expected a failure")
        } catch {
            #expect("\(error)".contains("exit status 1: no such device"))
        }
    }
}

@Suite struct PanelsTests {
    private func display(_ name: String, _ state: String) -> Display {
        Display(name: name, backlightState: state, nativeSize: [1398, 2034], pointScale: 3)
    }

    @Test func closedDuoLightsTheOuterPanel() throws {
        let displays = try Devicectl.decodeDisplays(fixture("displays-closed"))
        let lit = try Panels.litPanel(in: displays)
        #expect(lit.name == "LCD")
        #expect(displays[1].isLit == false)
    }

    @Test(arguments: ["activeOn", "inactiveOn", "activeDimmed"])
    func litStates(state: String) throws {
        let lit = try Panels.litPanel(in: [display("A", "off"), display("B", state)])
        #expect(lit.name == "B")
    }

    @Test func noLitPanelIsAnError() {
        #expect(throws: DuoError.litPanelCount(0, names: [])) {
            try Panels.litPanel(in: [display("A", "off"), display("B", "inactiveOff")])
        }
    }

    @Test func twoLitPanelsIsAnError() {
        #expect(throws: DuoError.litPanelCount(2, names: ["A", "B"])) {
            try Panels.litPanel(in: [display("A", "activeOn"), display("B", "activeDimmed")])
        }
        #expect(DuoError.litPanelCount(2, names: ["A", "B"]).description.contains("found 2"))
    }

    @Test func emptyListIsAnError() {
        #expect(throws: DuoError.noDisplays) { try Panels.litPanel(in: []) }
    }

    @Test func pointSizeIsPixelsOverScale() throws {
        let displays = try Devicectl.decodeDisplays(fixture("displays-closed"))
        #expect(displays[0].pointSize == Size(width: 466, height: 678))
        #expect(displays[1].pointSize == Size(width: 669, height: 951))
        #expect(displays[0].pointSize?.text == "466x678")
    }

    @Test func tableHasOneLinePerDisplay() throws {
        let displays = try Devicectl.decodeDisplays(fixture("displays-closed"))
        #expect(
            Panels.table(displays) == [
                "LCD    lit   1398x2034 px  466x678 pt  rot0",
                "LCD-1  dark  2007x2853 px  669x951 pt  rot90",
            ]
        )
    }
}
