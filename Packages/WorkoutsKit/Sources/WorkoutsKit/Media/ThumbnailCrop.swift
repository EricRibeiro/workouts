import CoreGraphics
import Foundation

/// The part of an exercise thumbnail that holds the figure, in unit coordinates (0...1, origin top-left).
public nonisolated struct CropRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    /// Clamps the rectangle to the unit square. Nil when a value is not finite or nothing of the rectangle is left.
    public init?(x: Double, y: Double, width: Double, height: Double) {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else { return nil }
        let left = min(max(x, 0), 1)
        let top = min(max(y, 0), 1)
        let right = min(max(x + width, 0), 1)
        let bottom = min(max(y + height, 0), 1)
        guard right > left, bottom > top else { return nil }
        self.x = left
        self.y = top
        self.width = right - left
        self.height = bottom - top
    }

    /// Where to draw the whole image so this rectangle is aspect-fitted and centred in a frame.
    public struct Placement: Equatable, Sendable {
        /// The size to draw the whole image at. The image keeps its aspect; its scale is `size.width` over its pixel width.
        public let size: CGSize
        /// The image's top-leading corner relative to the frame's. Usually negative: the rest of the image is clipped.
        public let offset: CGSize
    }

    /// The placement that shows this rectangle as large as it fits in `frame`, centred, with the image's aspect kept.
    /// - Parameters:
    ///   - imageAspect: The image's pixel width over height (178 / 100 for the bundled thumbnails).
    ///   - frame: The frame in points. Nil when it or `imageAspect` is not positive and finite.
    public func placement(imageAspect: Double, in frame: CGSize) -> Placement? {
        let frameWidth = Double(frame.width)
        let frameHeight = Double(frame.height)
        guard imageAspect.isFinite, imageAspect > 0, frameWidth.isFinite, frameWidth > 0, frameHeight.isFinite,
            frameHeight > 0
        else { return nil }
        // Measure in points per unit of image height, so the image is `imageAspect` wide and 1 tall.
        let scale = min(frameWidth / (width * imageAspect), frameHeight / height)
        let drawnWidth = imageAspect * scale
        let drawnHeight = scale
        let centreX = (x + width / 2) * drawnWidth
        let centreY = (y + height / 2) * drawnHeight
        return Placement(
            size: CGSize(width: drawnWidth, height: drawnHeight),
            offset: CGSize(width: frameWidth / 2 - centreX, height: frameHeight / 2 - centreY)
        )
    }
}

/// The bundled `Library/thumbs/thumb-crops.json`: `{ "<exercise id>": [x, y, w, h] }`, written by `./dev thumb-crops`.
nonisolated struct ThumbnailCropManifest: Sendable {
    let crops: [String: CropRect]

    static let empty = ThumbnailCropManifest(crops: [:])

    /// Entries that are not four finite numbers, or that leave nothing inside the image, are dropped; a file that is
    /// not a JSON object of arrays yields an empty manifest.
    init(data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            self.crops = [:]
            return
        }
        var crops: [String: CropRect] = [:]
        for (id, value) in object {
            guard let numbers = value as? [Double], numbers.count == 4,
                let rect = CropRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
            else { continue }
            crops[id] = rect
        }
        self.crops = crops
    }

    private init(crops: [String: CropRect]) { self.crops = crops }

    static func load(from bundle: Bundle) -> ThumbnailCropManifest {
        guard let url = bundle.url(forResource: "thumb-crops", withExtension: "json", subdirectory: "Library/thumbs"),
            let data = try? Data(contentsOf: url)
        else { return .empty }
        return ThumbnailCropManifest(data: data)
    }
}

/// Reads the manifest on first use, then serves every later lookup from memory.
nonisolated final class ThumbnailCropCache: @unchecked Sendable {
    private let bundle: Bundle
    private let lock = NSLock()
    private var manifest: ThumbnailCropManifest?

    init(bundle: Bundle) { self.bundle = bundle }

    func crop(for id: UUID) -> CropRect? {
        lock.withLock {
            if manifest == nil { manifest = .load(from: bundle) }
            return manifest?.crops[id.uuidString]
        }
    }
}
