import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// `--burst <count>x<intervalMs>`: how many captures, and the target spacing between their starts.
public struct BurstSpec: Sendable, Equatable {
    public static let defaultCount = 15
    public static let defaultIntervalMs = 100
    public static let countRange = 2...60
    public static let intervalRange = 10...5000

    public var count: Int
    public var intervalMs: Int

    public init(count: Int = BurstSpec.defaultCount, intervalMs: Int = BurstSpec.defaultIntervalMs) {
        self.count = count
        self.intervalMs = intervalMs
    }

    /// `15x100`. Throws `DuoError.verificationFailed` with the accepted form when the text or a range is off.
    public static func parse(_ text: String) throws -> BurstSpec {
        let parts = text.lowercased().split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2, let count = Int(parts[0]), let interval = Int(parts[1]) else {
            throw DuoError.verificationFailed(
                "--burst must look like <count>x<intervalMs>, e.g. 15x100 (got '\(text)')"
            )
        }
        guard countRange.contains(count) else {
            throw DuoError.verificationFailed("--burst count must be in \(countRange) (got \(count))")
        }
        guard intervalRange.contains(interval) else {
            throw DuoError.verificationFailed("--burst interval must be in \(intervalRange) ms (got \(interval))")
        }
        return BurstSpec(count: count, intervalMs: interval)
    }

    /// Finds `--burst` or `--burst=<spec>` in `arguments`. A bare `--burst` (nothing after it, or a next argument that
    /// does not start with a digit) means the default 15x100. Returns nil when the flag is absent.
    public static func parse(arguments: [String]) throws -> BurstSpec? {
        for (index, argument) in arguments.enumerated() {
            if argument.hasPrefix("--burst=") { return try parse(String(argument.dropFirst("--burst=".count))) }
            if argument == "--burst" {
                if index + 1 < arguments.count, arguments[index + 1].first?.isNumber == true {
                    return try parse(arguments[index + 1])
                }
                return BurstSpec()
            }
        }
        return nil
    }
}

/// One burst capture: the PNG on disk and when its capture began, relative to the first.
public struct BurstFrame: Sendable, Equatable {
    public var path: String
    public var elapsedMs: Int

    public init(path: String, elapsedMs: Int) {
        self.path = path
        self.elapsedMs = elapsedMs
    }

    /// `#3 +412ms`; the index is zero-based, the label one-based.
    public static func label(index: Int, elapsedMs: Int) -> String { "#\(index + 1) +\(elapsedMs)ms" }
}

/// Where each frame sits in the contact sheet. Pure arithmetic, no drawing.
public struct BurstLayout: Sendable, Equatable {
    public static let defaultColumns = 5
    public static let maxTileWidth = 360
    public static let gutter = 8
    public static let labelHeight = 22

    public var count: Int
    public var columns: Int
    public var tileWidth: Int
    public var tileHeight: Int

    public var rows: Int { (count + columns - 1) / columns }
    public var cellHeight: Int { tileHeight + BurstLayout.labelHeight }
    public var width: Int { columns * tileWidth + (columns + 1) * BurstLayout.gutter }
    public var height: Int { rows * cellHeight + (rows + 1) * BurstLayout.gutter }

    /// Tiles keep the frame's aspect ratio and are scaled down (never up) to `maxTileWidth`. Columns never exceed
    /// `count`, so a short burst is not padded with empty columns.
    public init(count: Int, frameWidth: Int, frameHeight: Int, columns: Int = BurstLayout.defaultColumns) {
        self.count = max(count, 0)
        self.columns = max(1, min(columns, max(count, 1)))
        let width = max(1, min(frameWidth, BurstLayout.maxTileWidth))
        self.tileWidth = width
        self.tileHeight = max(1, Int((Double(frameHeight) * Double(width) / Double(max(frameWidth, 1))).rounded()))
    }

    /// Top-left of frame `index`'s tile in a top-left-origin sheet (the label sits above the tile).
    public func origin(of index: Int) -> (x: Int, y: Int) {
        let row = index / columns
        let column = index % columns
        let x = BurstLayout.gutter + column * (tileWidth + BurstLayout.gutter)
        let y = BurstLayout.gutter + row * (cellHeight + BurstLayout.gutter) + BurstLayout.labelHeight
        return (x, y)
    }
}

public enum BurstSheet {
    /// Reads every frame, tiles them row by row with a `#n +ms` label above each, and writes one PNG to `output`.
    public static func compose(frames: [BurstFrame], columns: Int = BurstLayout.defaultColumns, output: String) throws {
        guard !frames.isEmpty else { throw DuoError.verificationFailed("burst took no frames") }
        let images = try frames.map { try load($0.path) }
        let layout = BurstLayout(
            count: frames.count,
            frameWidth: images[0].width,
            frameHeight: images[0].height,
            columns: columns
        )
        guard
            let context = CGContext(
                data: nil,
                width: layout.width,
                height: layout.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw DuoError.verificationFailed("could not create a \(layout.width)x\(layout.height) bitmap") }
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: layout.width, height: layout.height))
        context.interpolationQuality = .high
        for (index, image) in images.enumerated() {
            let origin = layout.origin(of: index)
            // CoreGraphics' origin is bottom-left; the layout's is top-left.
            let tile = CGRect(
                x: origin.x,
                y: layout.height - origin.y - layout.tileHeight,
                width: layout.tileWidth,
                height: layout.tileHeight
            )
            context.draw(image, in: tile)
            drawLabel(
                BurstFrame.label(index: index, elapsedMs: frames[index].elapsedMs),
                at: CGPoint(x: tile.minX, y: tile.maxY + 6),
                in: context
            )
        }
        guard let sheet = context.makeImage() else { throw DuoError.verificationFailed("could not render the sheet") }
        let url = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw DuoError.verificationFailed("could not write \(output)") }
        CGImageDestinationAddImage(destination, sheet, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DuoError.verificationFailed("could not write \(output)")
        }
    }

    private static func load(_ path: String) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw DuoError.verificationFailed("could not read the burst frame \(path)") }
        return image
    }

    private static func drawLabel(_ text: String, at point: CGPoint, in context: CGContext) {
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, 14, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }
}

private final class BurstFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [any Error] = []
    func record(_ error: any Error) { lock.withLock { errors.append(error) } }
    var first: (any Error)? { lock.withLock { errors.first } }
}

extension Screenshot {
    /// `simctl io screenshot` takes about 450 ms, so captures overlap: at most this many run at once.
    public static let maxInFlight = 8

    /// Starts capture `i` of the resolved panel at `i * intervalMs` after the first, each in its own `simctl`
    /// process (they overlap, so a slow capture does not delay the next start). A frame's `elapsedMs` is when its
    /// capture started; the framebuffer is read somewhere within the following few hundred ms, so offsets are
    /// approximate. The display is resolved once, up front. Frames are written to `directory` as `frame-<n>.png`.
    public static func burst(
        spec: BurstSpec,
        directory: String,
        udid: String,
        selector: DisplaySelector = .lit,
        runner: any ProcessRunning = SystemProcessRunner(),
        now: () -> Date = Date.init,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws -> (frames: [BurstFrame], display: Display) {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let display = try resolveDisplay(udid: udid, selector: selector, runner: runner, sleep: sleep)
        let simctl = Simctl(runner: runner)
        let failures = BurstFailures()
        let inFlight = DispatchSemaphore(value: maxInFlight)
        let group = DispatchGroup()
        let start = now()
        var frames: [BurstFrame] = []
        let name = display.name
        for index in 0..<spec.count {
            let due = Double(index * spec.intervalMs) / 1000
            let wait = due - now().timeIntervalSince(start)
            if wait > 0 { sleep(wait) }
            let elapsedMs = Int((now().timeIntervalSince(start) * 1000).rounded())
            let path = (directory as NSString).appendingPathComponent("frame-\(index + 1).png")
            frames.append(BurstFrame(path: path, elapsedMs: elapsedMs))
            inFlight.wait()
            DispatchQueue.global().async(group: group) {
                defer { inFlight.signal() }
                do {
                    try simctl.screenshot(udid: udid, displayName: name, path: path)
                } catch {
                    failures.record(error)
                }
            }
        }
        group.wait()
        if let error = failures.first { throw error }
        return (frames, display)
    }
}
