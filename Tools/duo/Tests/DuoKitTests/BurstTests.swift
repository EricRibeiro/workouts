import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import DuoKit

@Suite struct BurstSpecTests {
    @Test func parsesCountAndInterval() throws {
        #expect(try BurstSpec.parse("15x100") == BurstSpec(count: 15, intervalMs: 100))
        #expect(try BurstSpec.parse("8X250") == BurstSpec(count: 8, intervalMs: 250))
    }

    @Test(arguments: ["", "15", "x100", "15x", "ax1", "15x100x2", "1x100", "61x100", "15x9", "15x5001", "-3x100"])
    func rejectsMalformedOrOutOfRange(text: String) {
        #expect(throws: DuoError.self) { try BurstSpec.parse(text) }
    }

    @Test func defaultsAreFifteenTimesHundred() {
        #expect(BurstSpec() == BurstSpec(count: 15, intervalMs: 100))
    }

    @Test func findsTheFlagInArguments() throws {
        #expect(try BurstSpec.parse(arguments: ["out.png", "--udid", "U"]) == nil)
        #expect(
            try BurstSpec.parse(arguments: ["out.png", "--burst", "6x200", "--udid", "U"])
                == BurstSpec(count: 6, intervalMs: 200)
        )
        #expect(try BurstSpec.parse(arguments: ["out.png", "--burst=6x200"]) == BurstSpec(count: 6, intervalMs: 200))
    }

    @Test func bareFlagMeansTheDefault() throws {
        #expect(try BurstSpec.parse(arguments: ["out.png", "--burst"]) == BurstSpec())
        #expect(try BurstSpec.parse(arguments: ["out.png", "--burst", "--udid", "U"]) == BurstSpec())
    }

    @Test func aBadValueAfterTheFlagThrows() {
        #expect(throws: DuoError.self) { try BurstSpec.parse(arguments: ["--burst", "9"]) }
    }
}

@Suite struct BurstLayoutTests {
    @Test func scalesTilesDownKeepingAspect() {
        let layout = BurstLayout(count: 15, frameWidth: 1398, frameHeight: 2034)
        #expect(layout.tileWidth == 360)
        #expect(layout.tileHeight == 524)  // 2034 * 360 / 1398
        #expect(layout.columns == 5)
        #expect(layout.rows == 3)
    }

    @Test func neverScalesUp() {
        let layout = BurstLayout(count: 4, frameWidth: 200, frameHeight: 300)
        #expect(layout.tileWidth == 200)
        #expect(layout.tileHeight == 300)
    }

    @Test func roundsRowsUpAndTrimsColumnsForShortBursts() {
        #expect(BurstLayout(count: 11, frameWidth: 360, frameHeight: 720).rows == 3)
        let short = BurstLayout(count: 3, frameWidth: 360, frameHeight: 720)
        #expect(short.columns == 3)
        #expect(short.rows == 1)
    }

    @Test func sheetSizeIncludesGuttersAndLabels() {
        let layout = BurstLayout(count: 10, frameWidth: 360, frameHeight: 720)
        let gutter = BurstLayout.gutter
        #expect(layout.width == 5 * 360 + 6 * gutter)
        #expect(layout.height == 2 * (720 + BurstLayout.labelHeight) + 3 * gutter)
    }

    @Test func originsRunLeftToRightThenDown() {
        let layout = BurstLayout(count: 7, frameWidth: 360, frameHeight: 720)
        let first = layout.origin(of: 0)
        let second = layout.origin(of: 1)
        let sixth = layout.origin(of: 5)
        #expect(first.x == BurstLayout.gutter)
        #expect(first.y == BurstLayout.gutter + BurstLayout.labelHeight)
        #expect(second.x == first.x + 360 + BurstLayout.gutter)
        #expect(second.y == first.y)
        #expect(sixth.x == first.x)
        #expect(sixth.y == first.y + layout.cellHeight + BurstLayout.gutter)
    }

    @Test func labelsAreOneBased() {
        #expect(BurstFrame.label(index: 0, elapsedMs: 0) == "#1 +0ms")
        #expect(BurstFrame.label(index: 2, elapsedMs: 412) == "#3 +412ms")
    }
}

/// Serves a PNG for every `simctl io screenshot` and the closed-Duo fixture for `devicectl`; counts both.
private final class BurstRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var devicectlCalls = 0
    private var simctlCalls = 0
    let failSimctl: Bool
    init(failSimctl: Bool = false) { self.failSimctl = failSimctl }
    var devicectl: Int { lock.withLock { devicectlCalls } }
    var simctl: Int { lock.withLock { simctlCalls } }

    func run(_ executable: String, arguments: [String]) throws -> ProcessOutput {
        if arguments.first == "devicectl" {
            lock.withLock { devicectlCalls += 1 }
            let url = try #require(
                Bundle.module.url(forResource: "displays-closed", withExtension: "json", subdirectory: "Fixtures")
            )
            return ProcessOutput(status: 0, stdout: try Data(contentsOf: url), stderr: "")
        }
        let index = lock.withLock { () -> Int in
            simctlCalls += 1
            return simctlCalls
        }
        if failSimctl { return ProcessOutput(status: 1, stdout: Data(), stderr: "boom") }
        try writePNG(to: arguments.last ?? "", gray: CGFloat(index % 5) / 5)
        return ProcessOutput(status: 0, stdout: Data(), stderr: "")
    }
}

private func writePNG(to path: String, gray: CGFloat, width: Int = 40, height: Int = 80) throws {
    let context = try #require(
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    context.setFillColor(CGColor(gray: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let destination = try #require(
        CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
    )
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}

private func pixelSize(of path: String) throws -> (width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
}

private func scratchDirectory() -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent("duo-burst-test-\(UUID().uuidString)").path
}

@Suite struct BurstCaptureTests {
    @Test func resolvesTheDisplayOnceAndCapturesEveryFrameOnSchedule() throws {
        let runner = BurstRunner()
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        var clock = Date(timeIntervalSince1970: 1000)
        let (frames, display) = try Screenshot.burst(
            spec: BurstSpec(count: 4, intervalMs: 100),
            directory: directory,
            udid: "U",
            runner: runner,
            now: { clock },
            sleep: { clock = clock.addingTimeInterval($0) }
        )
        #expect(display.name == "LCD")
        #expect(runner.devicectl == 1)
        #expect(runner.simctl == 4)
        #expect(frames.map(\.elapsedMs) == [0, 100, 200, 300])
        #expect(frames.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func aFailedCaptureFailsTheBurst() {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        #expect(throws: DuoError.self) {
            try Screenshot.burst(
                spec: BurstSpec(count: 3, intervalMs: 10),
                directory: directory,
                udid: "U",
                runner: BurstRunner(failSimctl: true),
                sleep: { _ in }
            )
        }
    }
}

@Suite struct BurstSheetTests {
    @Test func tilesFramesIntoOneGridPNG() throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var frames: [BurstFrame] = []
        for index in 0..<7 {
            let path = directory + "/f\(index).png"
            try writePNG(to: path, gray: CGFloat(index) / 7)
            frames.append(BurstFrame(path: path, elapsedMs: index * 100))
        }
        let output = directory + "/sheet.png"
        try BurstSheet.compose(frames: frames, output: output)
        let layout = BurstLayout(count: 7, frameWidth: 40, frameHeight: 80)
        let size = try pixelSize(of: output)
        #expect(size.width == layout.width)
        #expect(size.height == layout.height)
        #expect(layout.rows == 2)
    }

    @Test func refusesAnEmptyBurst() {
        #expect(throws: DuoError.self) { try BurstSheet.compose(frames: [], output: "/dev/null") }
    }

    @Test func reportsAnUnreadableFrame() {
        let frame = BurstFrame(path: "/nonexistent/frame.png", elapsedMs: 0)
        #expect(throws: DuoError.self) { try BurstSheet.compose(frames: [frame], output: "/dev/null") }
    }
}
