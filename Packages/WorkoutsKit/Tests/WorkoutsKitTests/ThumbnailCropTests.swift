import CoreGraphics
import Foundation
import Testing

@testable import WorkoutsKit

private let thumbnailAspect = 178.0 / 100.0

private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) throws -> CropRect {
    try #require(CropRect(x: x, y: y, width: w, height: h))
}

/// A throwaway bundle whose `Library/thumbs/thumb-crops.json` holds `manifest` (no file at all when nil).
private func makeBundle(manifest: String?) throws -> (bundle: Bundle, root: URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("crops-\(UUID().uuidString)")
    let thumbs = root.appendingPathComponent("Library/thumbs", isDirectory: true)
    try FileManager.default.createDirectory(at: thumbs, withIntermediateDirectories: true)
    if let manifest {
        try Data(manifest.utf8).write(to: thumbs.appendingPathComponent("thumb-crops.json"))
    }
    return (try #require(Bundle(url: root)), root)
}

private func store(manifest: String?) throws -> (MediaStore, URL) {
    let (bundle, root) = try makeBundle(manifest: manifest)
    return (MediaStore(source: nil, bundle: bundle, cacheDirectory: root.appendingPathComponent("cache")), root)
}

@Suite("CropRect")
struct CropRectTests {
    @Test func clampsToTheUnitSquare() throws {
        let clamped = try rect(-0.1, 0.5, 0.5, 0.8)
        #expect(clamped == (try rect(0, 0.5, 0.4, 0.5)))
        #expect(try rect(0.9, 0.9, 0.5, 0.5) == (try rect(0.9, 0.9, 0.1, 0.1)))
    }

    @Test func rejectsEmptyAndNonFiniteRects() {
        #expect(CropRect(x: 0.2, y: 0.2, width: 0, height: 0.5) == nil)
        #expect(CropRect(x: 0.2, y: 0.2, width: 0.5, height: -0.1) == nil)
        #expect(CropRect(x: 1.2, y: 0, width: 0.5, height: 0.5) == nil)
        #expect(CropRect(x: .nan, y: 0, width: 0.5, height: 0.5) == nil)
        #expect(CropRect(x: 0, y: 0, width: .infinity, height: 0.5) == nil)
    }

    @Test func centredCropFillsTheFrameHeight() throws {
        // Crop 0.5 wide x 1.0 tall, centred: 0.89 units of aspect-width over 1 tall, so the height binds.
        let crop = try rect(0.25, 0, 0.5, 1)
        let placement = try #require(crop.placement(imageAspect: thumbnailAspect, in: CGSize(width: 64, height: 36)))
        #expect(abs(placement.size.height - 36) < 1e-9)
        #expect(abs(placement.size.width - 36 * thumbnailAspect) < 1e-9)
        // The crop centre (0.5, 0.5) lands on the frame centre, so the image is centred too.
        #expect(abs(placement.offset.width - (32 - placement.size.width / 2)) < 1e-9)
        #expect(abs(placement.offset.height - 0) < 1e-9)
    }

    @Test func offCentreCropMovesTheImage() throws {
        let crop = try rect(0.1, 0.2, 0.2, 0.4)
        let frame = CGSize(width: 64, height: 36)
        let placement = try #require(crop.placement(imageAspect: thumbnailAspect, in: frame))
        let centreX = (crop.x + crop.width / 2) * placement.size.width + placement.offset.width
        let centreY = (crop.y + crop.height / 2) * placement.size.height + placement.offset.height
        #expect(abs(centreX - 32) < 1e-9)
        #expect(abs(centreY - 18) < 1e-9)
        // Height binds (0.4 tall against 0.2 x 1.78 = 0.356 wide): 36 / 0.4 = 90 points per image height.
        #expect(abs(placement.size.height - 90) < 1e-9)
        #expect(abs(placement.offset.width - (32 - 0.2 * 1.78 * 90)) < 1e-9)
        #expect(abs(placement.offset.height - (18 - 0.4 * 90)) < 1e-9)
    }

    @Test func tallCropIsLimitedByTheFrameHeight() throws {
        let crop = try rect(0.4, 0, 0.1, 1)
        let frame = CGSize(width: 64, height: 36)
        let placement = try #require(crop.placement(imageAspect: thumbnailAspect, in: frame))
        #expect(abs(placement.size.height - 36) < 1e-9)
        let cropWidth = crop.width * placement.size.width
        #expect(cropWidth < 64)
        #expect(abs(cropWidth - 0.1 * 1.78 * 36) < 1e-9)
    }

    @Test func wideCropIsLimitedByTheFrameWidth() throws {
        let crop = try rect(0, 0.4, 1, 0.2)
        let frame = CGSize(width: 64, height: 36)
        let placement = try #require(crop.placement(imageAspect: thumbnailAspect, in: frame))
        #expect(abs(placement.size.width - 64) < 1e-9)
        #expect(abs(placement.offset.width) < 1e-9)
        let cropHeight = crop.height * placement.size.height
        #expect(cropHeight < 36)
        // Centred vertically: the crop's centre (0.5 of the image height) maps to the frame's centre.
        #expect(abs(0.5 * placement.size.height + placement.offset.height - 18) < 1e-9)
    }

    @Test func fullImageCropFitsTheFrame() throws {
        let crop = try rect(0, 0, 1, 1)
        let placement = try #require(crop.placement(imageAspect: thumbnailAspect, in: CGSize(width: 178, height: 100)))
        #expect(abs(placement.size.width - 178) < 1e-9)
        #expect(abs(placement.size.height - 100) < 1e-9)
        #expect(abs(placement.offset.width) < 1e-9)
        #expect(abs(placement.offset.height) < 1e-9)
    }

    @Test func degenerateInputsGiveNoPlacement() throws {
        let crop = try rect(0, 0, 0.5, 0.5)
        #expect(crop.placement(imageAspect: 0, in: CGSize(width: 64, height: 36)) == nil)
        #expect(crop.placement(imageAspect: thumbnailAspect, in: CGSize(width: 0, height: 36)) == nil)
        #expect(crop.placement(imageAspect: .nan, in: CGSize(width: 64, height: 36)) == nil)
    }
}

@Suite("MediaStore thumbnail crops")
struct ThumbnailCropStoreTests {
    private let id = UUID(uuidString: "0A1EFB9F-5FE6-513C-A01B-0B6BB42569BD")!

    @Test func readsAnEntryFromTheBundle() throws {
        let (store, root) = try store(manifest: #"{"0A1EFB9F-5FE6-513C-A01B-0B6BB42569BD": [0.1, 0.2, 0.3, 0.4]}"#)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(store.thumbnailCrop(for: id) == (try rect(0.1, 0.2, 0.3, 0.4)))
        #expect(store.thumbnailCrop(for: id) == (try rect(0.1, 0.2, 0.3, 0.4)))
    }

    @Test func missingIdIsNil() throws {
        let (store, root) = try store(manifest: #"{"0A1EFB9F-5FE6-513C-A01B-0B6BB42569BD": [0.1, 0.2, 0.3, 0.4]}"#)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(store.thumbnailCrop(for: UUID()) == nil)
    }

    @Test func missingFileIsNil() throws {
        let (store, root) = try store(manifest: nil)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(store.thumbnailCrop(for: id) == nil)
    }

    @Test(arguments: ["not json", "[1, 2, 3, 4]", #"{"0A1EFB9F-5FE6-513C-A01B-0B6BB42569BD": "oops"}"#, ""])
    func malformedFileIsNil(manifest: String) throws {
        let (store, root) = try store(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(store.thumbnailCrop(for: id) == nil)
    }

    @Test func badEntriesAreDroppedAndGoodOnesKept() throws {
        let other = UUID(uuidString: "0A5126A6-49EE-5C63-8F7B-D6E4E3F3A6AB")!
        let manifest = """
            {"0A1EFB9F-5FE6-513C-A01B-0B6BB42569BD": [0.1, 0.2, 0.3],
             "0A5126A6-49EE-5C63-8F7B-D6E4E3F3A6AB": [0.5, 0.5, 0.2, 0.2]}
            """
        let (store, root) = try store(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(store.thumbnailCrop(for: id) == nil)
        #expect(store.thumbnailCrop(for: other) == (try rect(0.5, 0.5, 0.2, 0.2)))
    }

    @Test func entriesOutsideTheImageAreClamped() throws {
        let (store, root) = try store(manifest: #"{"0A1EFB9F-5FE6-513C-A01B-0B6BB42569BD": [-0.05, 0.5, 0.5, 0.7]}"#)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(store.thumbnailCrop(for: id) == (try rect(0, 0.5, 0.45, 0.5)))
    }

    @Test func degenerateEntryIsNil() throws {
        let (store, root) = try store(manifest: #"{"0A1EFB9F-5FE6-513C-A01B-0B6BB42569BD": [0.5, 0.5, 0, 0.2]}"#)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(store.thumbnailCrop(for: id) == nil)
    }
}
