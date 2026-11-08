import CoreGraphics
import Testing

@testable import WorkoutsKit

@Suite struct FoldPlacementTests {
    typealias Placement = FoldPlacement.Placement

    private let both: FoldPlacement.Axes = [.horizontal, .vertical]
    /// A book-pose fold: a thin tall strip in the middle of an 800 x 600 area.
    private let bookFold = CGRect(x: 390, y: 0, width: 20, height: 600)
    /// A laptop-pose fold: a thin wide strip across the middle.
    private let laptopFold = CGRect(x: 0, y: 290, width: 800, height: 20)

    // MARK: Decision

    @Test func noAxesIsSingleEvenWithADivision() {
        let p = FoldPlacement.placement(size: CGSize(width: 800, height: 600), divisions: [bookFold], axes: [])
        #expect(p == Placement(kind: .single, lead: 0, gap: 0))
    }

    @Test func wideWithoutDivisionSplitsSideBySideInEqualHalves() {
        let p = FoldPlacement.placement(size: CGSize(width: 800, height: 600), divisions: [], axes: both)
        #expect(p == Placement(kind: .sideBySide, lead: 400, gap: 0))
    }

    @Test func tallWithoutDivisionStacksInEqualHalves() {
        let p = FoldPlacement.placement(size: CGSize(width: 600, height: 800), divisions: [], axes: both)
        #expect(p == Placement(kind: .stacked, lead: 400, gap: 0))
    }

    @Test func squareWithoutDivisionStacks() {
        let p = FoldPlacement.placement(size: CGSize(width: 500, height: 500), divisions: [], axes: both)
        #expect(p.kind == .stacked)
    }

    @Test func bookSplitsAtTheDivision() {
        let p = FoldPlacement.placement(size: CGSize(width: 800, height: 600), divisions: [bookFold], axes: both)
        #expect(p == Placement(kind: .sideBySide, lead: 390, gap: 20))
    }

    @Test func bookFramesKeepEachViewEntirelyOnItsSide() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let p = FoldPlacement.placement(size: bounds.size, divisions: [bookFold], axes: both)
        let frames = FoldPlacement.frames(for: p, in: bounds)
        #expect(frames.primary.maxX <= bookFold.minX)
        #expect(frames.secondary.minX >= bookFold.maxX)
        #expect(frames.primary.height == 600 && frames.secondary.height == 600)
        #expect(frames.header == nil)
    }

    @Test func laptopIsBenchWithSecondaryOnTop() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let p = FoldPlacement.placement(size: bounds.size, divisions: [laptopFold], axes: both)
        #expect(p == Placement(kind: .bench, lead: 290, gap: 20))
        #expect(p.isBench)
        let frames = FoldPlacement.frames(for: p, in: bounds)
        #expect(frames.secondary == CGRect(x: 0, y: 0, width: 800, height: 290))
        #expect(frames.primary == CGRect(x: 0, y: 310, width: 800, height: 290))
    }

    @Test func benchHeaderSitsAboveTheSecondaryAndIsCappedAtTheTopRegion() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let p = FoldPlacement.placement(size: bounds.size, divisions: [laptopFold], axes: both)
        let natural = FoldPlacement.frames(for: p, in: bounds, headerHeight: 60)
        #expect(natural.header == CGRect(x: 0, y: 0, width: 800, height: 60))
        #expect(natural.secondary == CGRect(x: 0, y: 60, width: 800, height: 230))
        let capped = FoldPlacement.frames(for: p, in: bounds, headerHeight: 1_000)
        #expect(capped.header?.height == 290)
        #expect(capped.secondary.height == 0)
        #expect(capped.primary.minY == 310)
    }

    @Test func keyboardUpInLaptopPoseSplitsTheShorterAreaByShape() {
        // The system drops the division and shrinks the area above the keyboard: 800 x 250 is wide, so side by side.
        let p = FoldPlacement.placement(size: CGSize(width: 800, height: 250), divisions: [], axes: both)
        #expect(p == Placement(kind: .sideBySide, lead: 400, gap: 0))
        // Back to bench mode when the keyboard goes.
        let back = FoldPlacement.placement(size: CGSize(width: 800, height: 600), divisions: [laptopFold], axes: both)
        #expect(back.isBench)
    }

    @Test func verticalOnlyAxesIgnoreABookDivision() {
        let p = FoldPlacement.placement(size: CGSize(width: 800, height: 600), divisions: [bookFold], axes: [.vertical])
        #expect(p == Placement(kind: .stacked, lead: 300, gap: 0))
    }

    @Test func horizontalOnlyAxesIgnoreALaptopDivision() {
        let wide = FoldPlacement.placement(
            size: CGSize(width: 800, height: 600),
            divisions: [laptopFold],
            axes: [.horizontal]
        )
        #expect(wide == Placement(kind: .sideBySide, lead: 400, gap: 0))
        // Tall and horizontal only: nothing to split along, so the primary gets everything.
        let tall = FoldPlacement.placement(
            size: CGSize(width: 600, height: 800),
            divisions: [laptopFold],
            axes: [.horizontal]
        )
        #expect(tall.kind == .single)
    }

    @Test func bothDivisionShapesPreferBenchWhenVerticalAllowed() {
        let p = FoldPlacement.placement(
            size: CGSize(width: 800, height: 600),
            divisions: [bookFold, laptopFold],
            axes: both
        )
        #expect(p.kind == .bench)
    }

    @Test func aSquareDivisionIsNeitherShape() {
        let odd = CGRect(x: 100, y: 100, width: 20, height: 20)
        let p = FoldPlacement.placement(size: CGSize(width: 800, height: 600), divisions: [odd], axes: both)
        #expect(p == Placement(kind: .sideBySide, lead: 400, gap: 0))
    }

    @Test func negativeDivisionOriginClampsLeadToZero() {
        let spill = CGRect(x: -10, y: 0, width: 20, height: 600)
        let p = FoldPlacement.placement(size: CGSize(width: 800, height: 600), divisions: [spill], axes: both)
        #expect(p == Placement(kind: .sideBySide, lead: 0, gap: 20))
    }

    @Test func zeroSizeContainerDoesNotGoNegative() {
        let p = FoldPlacement.placement(size: .zero, divisions: [], axes: both)
        #expect(p == Placement(kind: .stacked, lead: 0, gap: 0))
        let frames = FoldPlacement.frames(for: p, in: .zero)
        #expect(frames.primary == .zero && frames.secondary == .zero)
    }

    // MARK: Frames

    @Test func singleGivesPrimaryEverythingAndSecondaryNothing() {
        let bounds = CGRect(x: 5, y: 7, width: 300, height: 400)
        let frames = FoldPlacement.frames(for: Placement(kind: .single, lead: 0, gap: 0), in: bounds)
        #expect(frames.primary == bounds)
        #expect(frames.secondary == CGRect(x: 5, y: 7, width: 0, height: 0))
    }

    @Test func stackedHalvesAreEqualAndOffsetByTheBoundsOrigin() {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 400)
        let p = FoldPlacement.placement(size: bounds.size, divisions: [], axes: both)
        let frames = FoldPlacement.frames(for: p, in: bounds)
        #expect(frames.primary == CGRect(x: 10, y: 20, width: 300, height: 200))
        #expect(frames.secondary == CGRect(x: 10, y: 220, width: 300, height: 200))
    }

    @Test func divisionBeyondTheBoundsClampsToAnEmptySecondary() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 600)
        let frames = FoldPlacement.frames(for: Placement(kind: .sideBySide, lead: 500, gap: 20), in: bounds)
        #expect(frames.primary.width == 400)
        #expect(frames.secondary.minX == 400)
        #expect(frames.secondary.width == 0)
    }

    @Test func benchDivisionBelowTheBottomClampsToAnEmptyPrimary() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 600)
        let frames = FoldPlacement.frames(for: Placement(kind: .bench, lead: 700, gap: 20), in: bounds)
        #expect(frames.secondary.height == 600)
        #expect(frames.primary.minY == 600)
        #expect(frames.primary.height == 0)
    }

    // MARK: Two columns

    @Test func columnGapIsTheFirstVerticalDivisionStrictlyInside() {
        #expect(FoldPlacement.columnGap(divisions: [bookFold], width: 800) == 390...410)
        #expect(FoldPlacement.columnGap(divisions: [], width: 800) == nil)
        #expect(FoldPlacement.columnGap(divisions: [laptopFold], width: 800) == nil)
        // Touching an edge is not inside.
        #expect(FoldPlacement.columnGap(divisions: [CGRect(x: 0, y: 0, width: 20, height: 600)], width: 800) == nil)
        #expect(FoldPlacement.columnGap(divisions: [CGRect(x: 780, y: 0, width: 20, height: 600)], width: 800) == nil)
    }

    @Test func columnWidthsSplitAroundTheDivisionOrEvenly() {
        let around = FoldPlacement.columnWidths(total: 800, division: 390...410, spacing: 12)
        #expect(around.left == 390 && around.gap == 20 && around.right == 390)
        let even = FoldPlacement.columnWidths(total: 800, division: nil, spacing: 12)
        #expect(even.left == 394 && even.gap == 12 && even.right == 394)
        // A division that leaves no room falls back to even columns.
        let outside = FoldPlacement.columnWidths(total: 300, division: 390...410, spacing: 12)
        #expect(outside.left == 144 && outside.right == 144)
        let tiny = FoldPlacement.columnWidths(total: 5, division: nil, spacing: 12)
        #expect(tiny.left == 0 && tiny.right == 0)
    }

    // MARK: Grid columns around the fold

    @Test func foldColumnsPutTheMiddleGutterOnAnOffCentreHinge() throws {
        // Open wide: a 951 pt display, hinge at x = 475.5, a 17 pt margin and a 64 pt bar strip on the trailing edge. The
        // grid starts at x = 17 and is 951 - 17 - 17 - 64 = 853 pt wide, so the hinge is at 458.5 in the grid's own space
        // and an inactive hinge reports no width.
        let hinge: CGFloat = 458.5
        let columns = try #require(
            FoldPlacement.foldColumns(width: 853, minimum: 160, spacing: 12, division: hinge...hinge)
        )
        #expect(columns.count == 4)
        // Two columns a side; the gutter between them is 12 pt, centred on the hinge.
        #expect(columns[1].spacingAfter == 12)
        let leftEdge = columns[0].width + 12 + columns[1].width
        #expect(abs(leftEdge - (hinge - 6)) < 0.001)
        #expect(abs(leftEdge + 12 - (hinge + 6)) < 0.001)
        // Nothing crosses and the grid still fills its width.
        let total = columns.reduce(0) { $0 + $1.width + $1.spacingAfter }
        #expect(abs(total - 853) < 0.001)
        #expect(columns.allSatisfy { $0.width >= 160 })
    }

    @Test func foldColumnsKeepAWideDivisionAsTheGutter() throws {
        let columns = try #require(
            FoldPlacement.foldColumns(width: 800, minimum: 160, spacing: 12, division: 390...410)
        )
        #expect(columns.count == 4)
        #expect(columns[1].spacingAfter == 20)
        #expect(columns[0].width + 12 + columns[1].width == 390)
    }

    @Test func foldColumnsAreNilWithoutAUsableDivision() {
        #expect(FoldPlacement.foldColumns(width: 800, minimum: 160, spacing: 12, division: nil) == nil)
        // A division at the edge is not inside the grid.
        #expect(FoldPlacement.foldColumns(width: 800, minimum: 160, spacing: 12, division: 0...20) == nil)
        // A half too narrow for one column at the minimum.
        #expect(FoldPlacement.foldColumns(width: 800, minimum: 500, spacing: 12, division: 400...400) == nil)
    }
}
