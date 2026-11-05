import Foundation

/// A size in pixels or points.
public struct Size: Sendable, Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// `1398x2034`; fractional values keep one decimal.
    public var text: String {
        "\(Size.format(width))x\(Size.format(height))"
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

extension Display {
    /// `backlightState` values that mean the panel is showing something.
    public static let litBacklightStates: Set<String> = ["activeOn", "inactiveOn", "activeDimmed"]

    public var isLit: Bool {
        backlightState.map(Display.litBacklightStates.contains) ?? false
    }

    /// Pixel size, when the JSON carried a two-element `nativeSize`.
    public var pixelSize: Size? {
        guard let nativeSize, nativeSize.count == 2 else { return nil }
        return Size(width: nativeSize[0], height: nativeSize[1])
    }

    /// True when the panel is a quarter turn away from the orientation `nativeSize` is expressed in.
    public var isQuarterTurned: Bool {
        func degrees(_ text: String?) -> Int? {
            guard let text, text.hasPrefix("rot") else { return nil }
            return Int(text.dropFirst(3))
        }
        guard let current = degrees(currentOrientation) else { return false }
        let native = degrees(nativeOrientation) ?? 0
        return ((current - native) % 180 + 180) % 180 == 90
    }

    /// Pixel size as a capture of the panel comes out now (width and height swap on a quarter turn).
    public var orientedPixelSize: Size? {
        guard let size = pixelSize else { return nil }
        return isQuarterTurned ? Size(width: size.height, height: size.width) : size
    }

    /// Point size as the app sees it now.
    public var orientedPointSize: Size? {
        guard let size = pointSize else { return nil }
        return isQuarterTurned ? Size(width: size.height, height: size.width) : size
    }

    /// Point size = `nativeSize / pointScale`.
    public var pointSize: Size? {
        guard let pixelSize, let pointScale, pointScale > 0 else { return nil }
        return Size(width: pixelSize.width / pointScale, height: pixelSize.height / pointScale)
    }
}

public enum Panels {
    /// The one lit display, or an error naming how many were lit.
    public static func litPanel(in displays: [Display]) throws -> Display {
        guard !displays.isEmpty else { throw DuoError.noDisplays }
        let lit = displays.filter(\.isLit)
        guard lit.count == 1, let panel = lit.first else {
            throw DuoError.litPanelCount(lit.count, names: lit.map(\.name))
        }
        return panel
    }

    /// One line per display: `LCD    lit   1398x2034 px  466x678 pt  rot0`.
    public static func table(_ displays: [Display]) -> [String] {
        let width = displays.map(\.name.count).max() ?? 0
        return displays.map { display in
            let name = display.name.padding(toLength: width, withPad: " ", startingAt: 0)
            let state = display.isLit ? "lit " : "dark"
            let pixels = display.pixelSize.map { "\($0.text) px" } ?? "? px"
            let points = display.pointSize.map { "\($0.text) pt" } ?? "? pt"
            let orientation = display.currentOrientation ?? "?"
            return "\(name)  \(state)  \(pixels)  \(points)  \(orientation)"
        }
    }
}
