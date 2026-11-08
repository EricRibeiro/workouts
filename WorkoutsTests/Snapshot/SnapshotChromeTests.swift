import Testing
import UIKit

@testable import Workouts

/// `Snapshot.assertSameChrome` has to absorb the glass of a bar sampling different content between two frames and still
/// catch a changed title or button. Synthetic bars: a light-gray "glass" capsule with a dark "glyph" block.
@MainActor
struct SnapshotChromeTests {
    private func bar(glass: CGFloat, glyphX: CGFloat?) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = Snapshot.scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 60), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 60))
            UIColor(white: glass, alpha: 1).setFill()
            context.fill(CGRect(x: 120, y: 10, width: 70, height: 40))
            if let glyphX {
                UIColor.black.setFill()
                context.fill(CGRect(x: glyphX, y: 20, width: 40, height: 14))
            }
        }
        return image.pngData() ?? Data()
    }

    @Test
    func glassShiftBehindTheBarIsTolerated() {
        Snapshot.assertSameChrome(bar(glass: 0.90, glyphX: 20), bar(glass: 0.80, glyphX: 20), topPoints: 60)
    }

    @Test
    func movedTitleIsCaught() {
        withKnownIssue {
            Snapshot.assertSameChrome(bar(glass: 0.90, glyphX: 20), bar(glass: 0.90, glyphX: 30), topPoints: 60)
        }
    }

    @Test
    func missingTitleIsCaughtEvenWithAGlassShift() {
        withKnownIssue {
            Snapshot.assertSameChrome(bar(glass: 0.90, glyphX: 20), bar(glass: 0.80, glyphX: nil), topPoints: 60)
        }
    }

    @Test
    func failedCheckWritesBothFramesAndADiffMask() throws {
        let loading = bar(glass: 0.90, glyphX: 20)
        let loaded = bar(glass: 0.90, glyphX: 30)
        let directory = Snapshot.writeChromeEvidence(loading: loading, loaded: loaded, topPoints: 60)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        for name in ["loading.png", "loaded.png", "diff-mask.png"] {
            let data = try #require(
                FileManager.default.contents(atPath: directory + "/" + name),
                "\(name) was not written"
            )
            #expect(UIImage(data: data) != nil, "\(name) is not an image")
        }
    }
}
