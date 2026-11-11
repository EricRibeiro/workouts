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

    @Test func columnWidthsWidenAFlatHingeToTheSpacing() {
        // A flat-open hinge reports no width: the gutter is 12 pt centred on it, so the columns never touch.
        let flat = FoldPlacement.columnWidths(total: 800, division: 400...400, spacing: 12)
        #expect(flat.left == 394 && flat.gap == 12 && flat.right == 394)
        // Off centre (a bar strip on one side): the fold is the gutter and each column fills up to it.
        let offCentre = FoldPlacement.columnWidths(total: 853, division: 458.5...458.5, spacing: 12)
        #expect(offCentre.left == 452.5 && offCentre.gap == 12 && offCentre.right == 388.5)
        // A fold wider than the spacing keeps its own width.
        let wide = FoldPlacement.columnWidths(total: 800, division: 390...410, spacing: 12)
        #expect(wide.gap == 20)
    }

    @Test func columnWidthsFillEachSideUpToTheFold() {
        // Open wide with the bar strip trailing: 440 | 351 pt halves around a 12 pt fold.
        let leftWider = FoldPlacement.columnWidths(total: 803, division: 440...452, spacing: 12)
        #expect(leftWider.left == 440 && leftWider.gap == 12 && leftWider.right == 351)
        // The mirror image: the wider half on the right.
        let rightWider = FoldPlacement.columnWidths(total: 803, division: 351...363, spacing: 12)
        #expect(rightWider.left == 351 && rightWider.gap == 12 && rightWider.right == 440)
        // The widths total the container and nothing lies inside the fold.
        for widths in [leftWider, rightWider] {
            #expect(widths.left + widths.gap + widths.right == 803)
        }
        #expect(leftWider.left <= 440 && leftWider.left + leftWider.gap >= 452)
        #expect(rightWider.left <= 351 && rightWider.left + rightWider.gap >= 363)
        // The 831 pt container with the fold at 435-476 (a bar strip on the trailing edge).
        let duo = FoldPlacement.columnWidths(total: 831, division: 435...476, spacing: 12)
        #expect(duo.left == 435 && duo.gap == 41 && duo.right == 355)
    }

    @Test func columnWidthsFallBackToEvenWhenASideIsTooNarrow() {
        // The hinge sits 20 pt from the leading edge: the left column would be below the minimum.
        let narrow = FoldPlacement.columnWidths(total: 800, division: 20...20, spacing: 12, minimumColumn: 44)
        #expect(narrow.left == 394 && narrow.gap == 12 && narrow.right == 394)
        let trailing = FoldPlacement.columnWidths(total: 800, division: 780...780, spacing: 12, minimumColumn: 44)
        #expect(trailing.left == 394 && trailing.right == 394)
    }

    // MARK: Grid columns around the fold

    @Test func foldColumnsFillEachHalfUpToTheFoldOnAnOffCentreHinge() throws {
        // Open wide: a 951 pt display, hinge at x = 475.5, a 17 pt margin and a 64 pt bar strip on the trailing edge. The
        // grid starts at x = 17 and is 951 - 17 - 17 - 64 = 853 pt wide, so the hinge is at 458.5 in the grid's own space
        // and an inactive hinge reports no width. The halves are 452.5 and 388.5 pt around the 12 pt gutter.
        let hinge: CGFloat = 458.5
        let columns = try #require(
            FoldPlacement.foldColumns(width: 853, minimum: 160, spacing: 12, division: hinge...hinge)
        )
        #expect(columns.count == 4)
        // Equal within a half, different across the fold.
        let left = (452.5 - 12) / 2
        let right = (388.5 - 12) / 2
        #expect(columns[..<2].allSatisfy { abs($0.width - left) < 0.001 })
        #expect(columns[2...].allSatisfy { abs($0.width - right) < 0.001 })
        // The fold is the gutter: nothing lies inside the hinge's 12 pt division.
        #expect(abs(columns[1].spacingAfter - 12) < 0.001)
        let leftEdge = columns[0].width + 12 + columns[1].width
        #expect(abs(leftEdge - 452.5) < 0.001)
        #expect(abs(leftEdge + columns[1].spacingAfter - (hinge + 6)) < 0.001)
        // The grid still fills its width, outer margins untouched.
        let total = columns.reduce(0) { $0 + $1.width + $1.spacingAfter }
        #expect(abs(total - 853) < 0.001)
        #expect(columns.allSatisfy { $0.width >= 160 })
    }

    @Test func foldColumnsMirrorWhenTheWiderHalfIsOnTheRight() throws {
        // 351 | 440 around a 12 pt fold in a 803 pt grid, and its mirror 440 | 351.
        let columns = try #require(
            FoldPlacement.foldColumns(width: 803, minimum: 160, spacing: 12, division: 351...363)
        )
        let mirrored = try #require(
            FoldPlacement.foldColumns(width: 803, minimum: 160, spacing: 12, division: 440...452)
        )
        #expect(columns.count == 4 && mirrored.count == 4)
        #expect(columns[..<2].allSatisfy { abs($0.width - (351 - 12) / 2) < 0.001 })
        #expect(columns[2...].allSatisfy { abs($0.width - (440 - 12) / 2) < 0.001 })
        #expect(mirrored[..<2].allSatisfy { abs($0.width - (440 - 12) / 2) < 0.001 })
        #expect(mirrored[2...].allSatisfy { abs($0.width - (351 - 12) / 2) < 0.001 })
        #expect(abs(columns[1].spacingAfter - 12) < 0.001 && abs(mirrored[1].spacingAfter - 12) < 0.001)
        for grid in [columns, mirrored] {
            let total = grid.reduce(0) { $0 + $1.width + $1.spacingAfter }
            #expect(abs(total - 803) < 0.001)
        }
    }

    @Test func foldColumnsSplitUnequalHalvesIntoTwoPlusTwoColumns() throws {
        // 435 | 355 around a 41 pt fold in an 831 pt grid: two columns a side, equal within a side.
        let columns = try #require(
            FoldPlacement.foldColumns(width: 831, minimum: 160, spacing: 12, division: 435...476)
        )
        #expect(columns.count == 4)
        #expect(columns[..<2].allSatisfy { abs($0.width - (435 - 12) / 2) < 0.001 })
        #expect(columns[2...].allSatisfy { abs($0.width - (355 - 12) / 2) < 0.001 })
        #expect(abs(columns[1].spacingAfter - 41) < 0.001)
        let total = columns.reduce(0) { $0 + $1.width + $1.spacingAfter }
        #expect(abs(total - 831) < 0.001)
    }

    @Test func foldColumnsAreOnePerHalfWhenOnlyOneFits() throws {
        // Halves are 394 and 354 pt; neither holds two 300 pt columns, so each has one, filling its own half.
        let columns = try #require(
            FoldPlacement.foldColumns(width: 760, minimum: 300, spacing: 12, division: 400...400)
        )
        #expect(columns.count == 2)
        #expect(abs(columns[0].width - 394) < 0.001 && abs(columns[1].width - 354) < 0.001)
        #expect(abs(columns[0].spacingAfter - 12) < 0.001)
        #expect(columns[1].spacingAfter == 0)
    }

    @Test func foldColumnsGutterAlwaysContainsTheDivision() throws {
        for hinge in stride(from: CGFloat(330), through: 520, by: 10) {
            let columns = try #require(
                FoldPlacement.foldColumns(width: 850, minimum: 160, spacing: 12, division: hinge...(hinge + 8))
            )
            let perHalf = columns.count / 2
            let lowerEnd = columns[..<perHalf].reduce(0) { $0 + $1.width } + 12 * CGFloat(perHalf - 1)
            let gutter = columns[perHalf - 1].spacingAfter
            #expect(lowerEnd <= hinge + 0.001)
            #expect(lowerEnd + gutter >= hinge + 8 - 0.001)
            #expect(lowerEnd + gutter >= lowerEnd + 12 - 0.001)
        }
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
    }

    @Test func foldColumnsKeepOnePerSideWhenTheScaledMinimumOutgrowsASide() throws {
        // Half-folded open Duo at xxxLarge: sides 435 and 351 pt, minimum 379 pt.
        let columns = try #require(
            FoldPlacement.foldColumns(width: 798, minimum: 379, spacing: 12, division: 435...447)
        )
        #expect(columns.count == 2)
        #expect(abs(columns[0].width - 435) < 0.001 && abs(columns[1].width - 351) < 0.001)
        #expect(abs(columns[0].spacingAfter - 12) < 0.001)
        #expect(columns[1].spacingAfter == 0)
    }

    @Test func foldColumnsAreUnchangedWhenTheMinimumFitsBothSides() throws {
        // The same sides at the default minimum of 280 pt: one column each, as before the floor existed.
        let columns = try #require(
            FoldPlacement.foldColumns(width: 798, minimum: 280, spacing: 12, division: 435...447)
        )
        #expect(columns.count == 2)
        #expect(abs(columns[0].width - 435) < 0.001 && abs(columns[1].width - 351) < 0.001)
    }

    @Test func foldColumnsAreNilWhenASideIsUnderTheFloor() {
        #expect(FoldPlacement.foldColumns(width: 800, minimum: 280, spacing: 12, division: 100...100) == nil)
        #expect(FoldPlacement.foldColumns(width: 800, minimum: 280, spacing: 12, division: 700...700) == nil)
        #expect(
            FoldPlacement.foldColumns(width: 800, minimum: 280, spacing: 12, division: 400...400, floor: 400) == nil
        )
    }

    @Test func foldColumnsGiveAWideSideItsColumnsBesideANarrowSideAtTheFloor() throws {
        // Leading 594 pt fits two 280 pt columns; trailing 194 pt fits none at the minimum but reaches the floor.
        let columns = try #require(
            FoldPlacement.foldColumns(width: 800, minimum: 280, spacing: 12, division: 600...600)
        )
        #expect(columns.count == 3)
        #expect(abs(columns[0].width - 291) < 0.001 && abs(columns[1].width - 291) < 0.001)
        #expect(abs(columns[2].width - 194) < 0.001)
        #expect(abs(columns[1].spacingAfter - 12) < 0.001)
        #expect(columns[2].spacingAfter == 0)
    }

    // MARK: Two pages on the hinge

    @Test func pagesFillEachSideOfAnOffCentreHinge() {
        // Open-wide Duo: 951 pt wide, hinge 455-496, the trailing strip's 88 pt already outside the container.
        let pages = FoldPlacement.pageFrames(total: 951, division: 455...496, margin: 17)
        let expected = FoldPlacement.PageFrames(
            leading: .init(x: 17, width: 438),
            trailing: .init(x: 496, width: 438)
        )
        #expect(pages == expected)
        let narrow = FoldPlacement.pageFrames(total: 851, division: 455...496, margin: 0)
        #expect(narrow?.leading == .init(x: 0, width: 455))
        #expect(narrow?.trailing == .init(x: 496, width: 355))
    }

    @Test func pagesMirrorWhenTheHingeSitsRightOfCentre() {
        let pages = FoldPlacement.pageFrames(total: 851, division: 396...437, margin: 0)
        #expect(pages?.leading == .init(x: 0, width: 396))
        #expect(pages?.trailing == .init(x: 437, width: 414))
        #expect(pages?.leading.maxX == 396)
    }

    @Test func pagesTouchTheDivisionAndOnlyTheOuterEdgesGetTheMargin() throws {
        let pages = try #require(FoldPlacement.pageFrames(total: 800, division: 390...410, margin: 16))
        #expect(pages.leading.x == 16)
        #expect(pages.leading.maxX == 390)
        #expect(pages.trailing.x == 410)
        #expect(pages.trailing.maxX == 784)
    }

    @Test func pagesAreNilWithoutADivision() {
        #expect(FoldPlacement.pageFrames(total: 800, division: nil, margin: 16) == nil)
    }

    @Test func pagesAreNilWhenTheHingeIsAtAnEdgeOrLeavesASliver() {
        #expect(FoldPlacement.pageFrames(total: 800, division: 0...20, margin: 0) == nil)
        #expect(FoldPlacement.pageFrames(total: 800, division: 780...800, margin: 0) == nil)
        #expect(FoldPlacement.pageFrames(total: 800, division: 30...50, margin: 0) == nil)
        #expect(FoldPlacement.pageFrames(total: 800, division: 380...420, margin: 380) == nil)
    }

    @Test func equalPagesShareTheWidthAroundTheSpacing() throws {
        let pages = try #require(FoldPlacement.equalPageFrames(total: 855, margin: 16, spacing: 16))
        #expect(pages.leading == .init(x: 16, width: 403.5))
        #expect(pages.trailing == .init(x: 435.5, width: 403.5))
        #expect(pages.trailing.maxX == 839)
    }

    @Test func equalPagesAreNilWhenAPageWouldBeTooNarrow() {
        #expect(FoldPlacement.equalPageFrames(total: 640, margin: 16, spacing: 16, minimumPage: 300) == nil)
        #expect(FoldPlacement.equalPageFrames(total: 650, margin: 16, spacing: 16, minimumPage: 300) != nil)
    }
}
