import CoreGraphics

/// Where the primary and secondary views go for the iPhone Duo fold poses: the pure decision behind the logging screen's
/// `BenchLayout` and the dashboard's two columns, kept out of SwiftUI so the geometry can be tested without a simulator.
///
/// Inputs are plain values read from the container: its size, the active `.division` regions' frames in the container's own
/// coordinate space (`GeometryProxy.reservedRegions(kind: .division, options: .includeInactive)`, split into the active
/// ones and the inactive ones), and the axes the arrangement may split along. While the keyboard is up in the laptop pose the system reports no division and a shorter
/// container, so that case is simply "no divisions, smaller size".
public nonisolated enum FoldPlacement {
    /// The axes an arrangement may split along (the kit's mirror of `Axis.Set`).
    public nonisolated struct Axes: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let horizontal = Axes(rawValue: 1)
        public static let vertical = Axes(rawValue: 2)
    }

    public nonisolated struct Placement: Equatable, Sendable {
        public nonisolated enum Kind: Equatable, Sendable {
            /// The primary gets the whole area; the secondary is collapsed.
            case single
            /// Primary on the left, secondary on the right.
            case sideBySide
            /// Primary above, secondary below.
            case stacked
            /// The hinge lies across the display: secondary (and the rest header) on top, primary below.
            case bench
        }

        public var kind: Kind
        /// The length of the first region along the split axis (its far edge); the gap follows it.
        public var lead: CGFloat
        /// The division's thickness, left empty between the two regions.
        public var gap: CGFloat

        public init(kind: Kind, lead: CGFloat, gap: CGFloat) {
            self.kind = kind
            self.lead = lead
            self.gap = gap
        }

        public var isBench: Bool { kind == .bench }
    }

    /// The decision. An active horizontal division (wider than tall, the laptop hinge) wins when the vertical axis is allowed
    /// and gives bench mode; an active vertical one (book) splits left/right when the horizontal axis is allowed. Inactive
    /// divisions (the hinge of a flat-open Duo, which the system reports but does not split on) are met too: a vertical one
    /// splits left/right on it, a horizontal one stacks the views on it, each leaving the division's thickness empty, so the
    /// two views meet at the hinge even when the container is off the display's centre (a bar strip on one side). An inactive
    /// division counts only when it lies strictly inside the container. With no usable division the area splits in two equal
    /// halves by its shape (wide: side by side, else stacked). No axes: single.
    public static func placement(
        size: CGSize,
        divisions: [CGRect],
        inactiveDivisions: [CGRect] = [],
        axes: Axes
    ) -> Placement {
        guard !axes.isEmpty else { return Placement(kind: .single, lead: 0, gap: 0) }
        if axes.contains(.vertical), let fold = divisions.first(where: { $0.width > $0.height }) {
            return Placement(kind: .bench, lead: max(0, fold.minY), gap: fold.height)
        }
        if axes.contains(.horizontal), let fold = divisions.first(where: { $0.width < $0.height }) {
            return Placement(kind: .sideBySide, lead: max(0, fold.minX), gap: fold.width)
        }
        if axes.contains(.horizontal),
            let fold = inactiveDivisions.first(where: { $0.width < $0.height && $0.minX > 0 && $0.maxX < size.width })
        {
            return Placement(kind: .sideBySide, lead: fold.minX, gap: fold.width)
        }
        if axes.contains(.vertical),
            let fold = inactiveDivisions.first(where: { $0.width > $0.height && $0.minY > 0 && $0.maxY < size.height })
        {
            return Placement(kind: .stacked, lead: fold.minY, gap: fold.height)
        }
        if size.width > size.height, axes.contains(.horizontal) {
            return Placement(kind: .sideBySide, lead: size.width / 2, gap: 0)
        }
        if axes.contains(.vertical) {
            return Placement(kind: .stacked, lead: size.height / 2, gap: 0)
        }
        return Placement(kind: .single, lead: 0, gap: 0)
    }

    /// The frames a `Placement` gives the views inside `bounds`.
    public nonisolated struct Frames: Equatable, Sendable {
        public var primary: CGRect
        public var secondary: CGRect
        /// The rest header above the secondary (bench mode only, and only when one was asked for).
        public var header: CGRect?
    }

    /// Resolves a placement into frames inside `bounds`. Lead and gap are clamped to the bounds so a division that spills
    /// outside leaves an empty (zero-size) region rather than a negative one. `headerHeight` is the natural height of the
    /// bench-mode header (nil when there is none); it is capped at the top region and pushes the secondary down.
    public static func frames(for placement: Placement, in bounds: CGRect, headerHeight: CGFloat? = nil) -> Frames {
        let origin = bounds.origin
        let size = bounds.size
        let lead = min(placement.lead, placement.kind == .sideBySide ? size.width : size.height)
        switch placement.kind {
        case .single:
            return Frames(
                primary: bounds,
                secondary: CGRect(origin: origin, size: .zero),
                header: nil
            )
        case .sideBySide:
            let trailingX = min(lead + placement.gap, size.width)
            return Frames(
                primary: CGRect(x: origin.x, y: origin.y, width: lead, height: size.height),
                secondary: CGRect(
                    x: origin.x + trailingX,
                    y: origin.y,
                    width: size.width - trailingX,
                    height: size.height
                ),
                header: nil
            )
        case .stacked:
            let lowerY = min(lead + placement.gap, size.height)
            return Frames(
                primary: CGRect(x: origin.x, y: origin.y, width: size.width, height: lead),
                secondary: CGRect(x: origin.x, y: origin.y + lowerY, width: size.width, height: size.height - lowerY),
                header: nil
            )
        case .bench:
            let lowerY = min(lead + placement.gap, size.height)
            var secondaryY = origin.y
            var header: CGRect?
            if let headerHeight {
                let height = min(headerHeight, lead)
                header = CGRect(x: origin.x, y: origin.y, width: size.width, height: height)
                secondaryY += height
            }
            return Frames(
                primary: CGRect(x: origin.x, y: origin.y + lowerY, width: size.width, height: size.height - lowerY),
                secondary: CGRect(
                    x: origin.x,
                    y: secondaryY,
                    width: size.width,
                    height: max(0, origin.y + lead - secondaryY)
                ),
                header: header
            )
        }
    }

    // MARK: Two columns

    /// The horizontal extent of the first active vertical division (taller than wide) when it lies strictly inside a
    /// container `width` wide, else nil. Used by layouts that flow content in two columns around the fold.
    public static func columnGap(divisions: [CGRect], width: CGFloat) -> ClosedRange<CGFloat>? {
        guard let frame = divisions.first(where: { $0.width < $0.height }) else { return nil }
        return frame.minX > 0 && frame.maxX < width ? frame.minX...frame.maxX : nil
    }

    /// Left width, gutter width and right width for two columns in `total`: both columns take the width of the narrower half
    /// around `division` when there is one that leaves room, so the outer margins stay and the wider half's surplus goes into
    /// the gutter, which still contains the division; else two equal columns around `spacing`. The gutter is the division
    /// widened to at least `spacing` around its centre (a flat-open hinge reports almost no width, and the columns must not
    /// touch). When either side would be narrower than `minimumColumn`, the split is even instead.
    public static func columnWidths(
        total: CGFloat,
        division: ClosedRange<CGFloat>?,
        spacing: CGFloat,
        minimumColumn: CGFloat = 44
    ) -> (left: CGFloat, gap: CGFloat, right: CGFloat) {
        if let division {
            let widen = max(0, spacing - (division.upperBound - division.lowerBound)) / 2
            let lower = division.lowerBound - widen
            let upper = division.upperBound + widen
            if lower >= minimumColumn, total - upper >= minimumColumn {
                let column = min(lower, total - upper)
                return (column, total - 2 * column, column)
            }
        }
        let column = max(0, (total - spacing) / 2)
        return (column, spacing, column)
    }

    // MARK: Two pages on the hinge

    /// A page's horizontal extent inside its container: x from the container's leading edge.
    public nonisolated struct PageFrame: Equatable, Sendable {
        public var x: CGFloat
        public var width: CGFloat

        public init(x: CGFloat, width: CGFloat) {
            self.x = x
            self.width = width
        }

        public var maxX: CGFloat { x + width }
    }

    /// The two pages of a screen split on the hinge.
    public nonisolated struct PageFrames: Equatable, Sendable {
        public var leading: PageFrame
        public var trailing: PageFrame

        public init(leading: PageFrame, trailing: PageFrame) {
            self.leading = leading
            self.trailing = trailing
        }
    }

    /// The frames of two pages in a container `total` wide that each fill their own side of `division`: the leading page runs
    /// from `margin` to the division's leading edge, the trailing page from the division's trailing edge to `margin` short of
    /// the container's end, so the division is the only gutter and the halves may differ in width (a bar strip on one side).
    /// Nil when there is no division, when it does not lie strictly inside the container, or when either page would be
    /// narrower than `minimumPage`; the caller then stacks the pages.
    public static func pageFrames(
        total: CGFloat,
        division: ClosedRange<CGFloat>?,
        margin: CGFloat,
        minimumPage: CGFloat = 44
    ) -> PageFrames? {
        guard let division, division.lowerBound > 0, division.upperBound < total else { return nil }
        let leading = PageFrame(x: margin, width: division.lowerBound - margin)
        let trailing = PageFrame(x: division.upperBound, width: total - margin - division.upperBound)
        guard leading.width >= minimumPage, trailing.width >= minimumPage else { return nil }
        return PageFrames(leading: leading, trailing: trailing)
    }

    /// The frames of two equal pages in a container `total` wide, ignoring any hinge: `margin` on the outer edges and `spacing`
    /// between the pages. Nil when either page would be narrower than `minimumPage`; the caller then stacks the pages.
    public static func equalPageFrames(
        total: CGFloat,
        margin: CGFloat,
        spacing: CGFloat,
        minimumPage: CGFloat = 44
    ) -> PageFrames? {
        let width = (total - 2 * margin - spacing) / 2
        guard width >= minimumPage else { return nil }
        return PageFrames(
            leading: PageFrame(x: margin, width: width),
            trailing: PageFrame(x: margin + width + spacing, width: width)
        )
    }

    // MARK: Sections in columns

    /// Where one section goes: its frame inside the container (x from the container's leading edge, y from its top).
    public nonisolated struct SectionFrame: Equatable, Sendable {
        public var x: CGFloat
        public var y: CGFloat
        public var width: CGFloat
        public var height: CGFloat

        public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public var maxX: CGFloat { x + width }
        public var maxY: CGFloat { y + height }
    }

    /// The frames of every section and the container's total height.
    public nonisolated struct SectionLayout: Equatable, Sendable {
        public var frames: [SectionFrame]
        public var height: CGFloat

        public init(frames: [SectionFrame], height: CGFloat) {
            self.frames = frames
            self.height = height
        }
    }

    /// Places `count` sections in `columns` columns (1 or 2) inside a container `total` wide. One column, or a lone
    /// section, takes the full width and the sections stack `rowSpacing` apart. Two columns take the sections in turn
    /// (first left, second right, third left again), each column a top-aligned stack independent of the other, at the
    /// widths `columnWidths` gives around `division` (equal on both sides of an off-centre fold, nothing inside the
    /// gutter). `height(index, width)` is section `index`'s height when proposed `width`; it is asked once per section,
    /// at the width the section is placed at.
    public static func sectionFrames(
        count: Int,
        total: CGFloat,
        division: ClosedRange<CGFloat>?,
        columns: Int,
        columnSpacing: CGFloat,
        rowSpacing: CGFloat,
        height: (_ index: Int, _ width: CGFloat) -> CGFloat
    ) -> SectionLayout {
        guard count > 0 else { return SectionLayout(frames: [], height: 0) }
        let twoColumns = columns >= 2 && count > 1
        let widths = twoColumns ? columnWidths(total: total, division: division, spacing: columnSpacing) : nil
        let rightX = widths.map { $0.left + $0.gap } ?? 0
        var bottoms: [CGFloat] = [0, 0]
        var placed = [false, false]
        var frames: [SectionFrame] = []
        frames.reserveCapacity(count)
        for index in 0..<count {
            let column = twoColumns ? index % 2 : 0
            let width = widths.map { column == 0 ? $0.left : $0.right } ?? total
            let sectionHeight = height(index, width)
            let y = bottoms[column] + (placed[column] ? rowSpacing : 0)
            frames.append(
                SectionFrame(x: column == 0 ? 0 : rightX, y: y, width: width, height: sectionHeight)
            )
            bottoms[column] = y + sectionHeight
            placed[column] = true
        }
        return SectionLayout(frames: frames, height: max(bottoms[0], bottoms[1]))
    }

    // MARK: Grid columns around the fold

    /// One column of a grid: its width and the space after it (the gutter to the next column).
    public nonisolated struct GridColumn: Equatable, Sendable {
        public var width: CGFloat
        public var spacingAfter: CGFloat

        public init(width: CGFloat, spacingAfter: CGFloat) {
            self.width = width
            self.spacingAfter = spacingAfter
        }
    }

    /// The columns of a grid `width` wide whose middle gutter is `division`, so no card crosses the fold: the same number of
    /// columns before the division and after it, each at least `minimum` wide. The gutter is the division widened to at
    /// least `spacing` around its centre (an inactive hinge reports no width). The halves are unequal when the grid is off
    /// the display's centre (a bar strip on one side). Every column gets the width the narrower half gives it, so a card
    /// looks the same on both sides; the outer margins stay and the wider half's surplus goes into the gutter around the
    /// fold. Nil when there is no division inside the grid or a half cannot hold one column at `minimum`; the caller then
    /// uses its fold-less column count.
    public static func foldColumns(
        width: CGFloat,
        minimum: CGFloat,
        spacing: CGFloat,
        division: ClosedRange<CGFloat>?
    ) -> [GridColumn]? {
        guard let division else { return nil }
        let widen = max(0, spacing - (division.upperBound - division.lowerBound)) / 2
        let lower = division.lowerBound - widen
        let upper = division.upperBound + widen
        guard lower > 0, upper < width else { return nil }
        let trailing = width - upper
        func fit(_ half: CGFloat) -> Int { Int(((half + spacing) / (minimum + spacing)).rounded(.down)) }
        let perHalf = min(fit(lower), fit(trailing))
        guard perHalf >= 1 else { return nil }
        let narrow = min(lower, trailing)
        let column = (narrow - spacing * CGFloat(perHalf - 1)) / CGFloat(perHalf)
        func half(lastGap: CGFloat) -> [GridColumn] {
            (0..<perHalf).map { GridColumn(width: column, spacingAfter: $0 == perHalf - 1 ? lastGap : spacing) }
        }
        return half(lastGap: width - 2 * narrow) + half(lastGap: 0)
    }
}
