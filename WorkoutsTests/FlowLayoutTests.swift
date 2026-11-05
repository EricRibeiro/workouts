import CoreGraphics
import Testing

@testable import Workouts

struct FlowLayoutTests {
    private let chips = [
        CGSize(width: 120, height: 30), CGSize(width: 130, height: 30), CGSize(width: 150, height: 30),
    ]

    @Test func wrapsWhenTheNextChipDoesNotFit() {
        let result = FlowLayout.arrange(sizes: chips, in: 300, spacing: 8)
        #expect(result.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 128, y: 0), CGPoint(x: 0, y: 38)])
        #expect(result.size == CGSize(width: 258, height: 68))
    }

    /// The regression: the measured row is exactly as wide as the width, and a fraction less wraps one more row. Placement
    /// therefore arranges at the proposed width (what was measured), never at the pixel-rounded bounds.
    @Test func aRowExactlyAsWideAsTheWidthStaysOneRow() {
        let measured = FlowLayout.arrange(sizes: chips, in: 258, spacing: 8)
        #expect(measured.size.height == 68)
        let rounded = FlowLayout.arrange(sizes: chips, in: 257.67, spacing: 8)
        #expect(rounded.size.height == 106)
    }

    @Test func aChipWiderThanTheWidthGetsItsOwnRow() {
        let result = FlowLayout.arrange(sizes: [CGSize(width: 400, height: 30), chips[0]], in: 300, spacing: 8)
        #expect(result.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 38)])
    }
}
