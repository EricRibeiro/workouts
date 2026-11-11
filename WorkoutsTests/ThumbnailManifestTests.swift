import Foundation
import Testing

/// The bundled `Library/thumbs` folder and its `thumb-crops.json` describe the same exercises.
struct ThumbnailManifestTests {
    private static let suffix = "-start.png"

    private func thumbsFolder() throws -> URL {
        let manifest = try #require(
            Bundle.main.url(forResource: "thumb-crops", withExtension: "json", subdirectory: "Library/thumbs"),
            "thumb-crops.json is not in the bundle"
        )
        return manifest.deletingLastPathComponent()
    }

    private func manifestIDs(in folder: URL) throws -> Set<String> {
        let data = try Data(contentsOf: folder.appending(path: "thumb-crops.json"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    private func startFrameIDs(in folder: URL) throws -> Set<String> {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        return Set(names.filter { $0.hasSuffix(Self.suffix) }.map { String($0.dropLast(Self.suffix.count)) })
    }

    @Test func everyStartFrameHasACropEntry() throws {
        let folder = try thumbsFolder()
        let frames = try startFrameIDs(in: folder)
        #expect(!frames.isEmpty)
        let missing = frames.subtracting(try manifestIDs(in: folder))
        #expect(missing.isEmpty, "start frames without a thumb-crops.json entry: \(missing.sorted().prefix(5))")
    }

    @Test func everyCropEntryHasItsStartFrame() throws {
        let folder = try thumbsFolder()
        let orphans = try manifestIDs(in: folder).subtracting(try startFrameIDs(in: folder))
        #expect(orphans.isEmpty, "crop entries without a start frame: \(orphans.sorted().prefix(5))")
    }
}
