//
//  BenchArrangement.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The arrangement style of the logging screen and the two editors (task 6.1): the primary (the set table) and secondary
/// (the exercise pane) in one fixed view tree, placed by `BenchLayout`, so folding never rebuilds the table and its focus and
/// scroll position survive every pose change.
///
/// It reproduces what the system's `.split.axes(axes)` does, measured on the Duo (6.2): with no active division the two halves
/// are equal (side by side when the area is wider than tall, primary above secondary otherwise); with the Duo half-open the
/// split follows the division region, so each view sits entirely on its own side of the fold (book: primary left, pane right).
/// One pose differs on purpose: half-open with the hinge across the display ("bench mode", laptop) puts the secondary on the
/// upper half, with the rest countdown above it while a rest runs, and the primary on the lower half, where the keyboard lands.
/// No axes (compact width, or no pane to show) gives the primary the whole area. While the keyboard is up in the laptop pose
/// the system takes the division out of the area above the keyboard; the arrangement then splits that area by its shape,
/// which keeps the focused table in view, and returns to bench mode when the keyboard goes.
///
/// The system style cannot be nested for the other poses: a different branch is a different structural identity, which
/// recreated the table (value kept, focus and scroll lost) when folding from book to laptop.
struct BenchArrangementStyle: ArrangementViewStyle {
    var axes: Axis.Set
    /// Whether bench mode puts the rest countdown above the exercise pane: the logging screen only (the editors have no rest).
    var showsRestCountdown = false

    func makeBody(configuration: Configuration) -> some View {
        BenchArrangementBody(configuration: configuration, axes: axes, showsRestCountdown: showsRestCountdown)
    }
}

private struct BenchArrangementBody: View {
    let configuration: ArrangementViewStyleConfiguration
    let axes: Axis.Set
    let showsRestCountdown: Bool

    var body: some View {
        GeometryReader { proxy in
            let placement = placement(in: proxy)
            BenchLayout(placement: placement) {
                configuration.primary
                configuration.secondary
                if placement.isBench, showsRestCountdown {
                    RestCountdownHeader()
                }
            }
        }
    }

    private func placement(in proxy: GeometryProxy) -> BenchLayout.Placement {
        guard !axes.isEmpty else { return .init(kind: .single, lead: 0, gap: 0) }
        let size = proxy.size
        let divisions = proxy.reservedRegions(kind: .division).filter(\.isActive)
        if axes.contains(.vertical), let fold = divisions.first(where: { $0.frame.width > $0.frame.height }) {
            return .init(kind: .bench, lead: max(0, fold.frame.minY), gap: fold.frame.height)
        }
        if axes.contains(.horizontal), let fold = divisions.first(where: { $0.frame.width < $0.frame.height }) {
            return .init(kind: .sideBySide, lead: max(0, fold.frame.minX), gap: fold.frame.width)
        }
        if size.width > size.height, axes.contains(.horizontal) {
            return .init(kind: .sideBySide, lead: size.width / 2, gap: 0)
        }
        if axes.contains(.vertical) {
            return .init(kind: .stacked, lead: size.height / 2, gap: 0)
        }
        return .init(kind: .single, lead: 0, gap: 0)
    }
}

/// Places the primary, the secondary and, in bench mode, the rest header (subviews in that order, the header last).
private struct BenchLayout: Layout {
    struct Placement: Equatable {
        enum Kind { case single, sideBySide, stacked, bench }
        var kind: Kind
        /// The length of the first region along the split axis (its far edge); the gap follows it.
        var lead: CGFloat
        /// The division's thickness, left empty between the two regions.
        var gap: CGFloat

        var isBench: Bool { kind == .bench }
    }

    var placement: Placement

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 2 else { return }
        let primary = subviews[0]
        let secondary = subviews[1]
        let origin = bounds.origin
        let lead = min(placement.lead, placement.kind == .sideBySide ? bounds.width : bounds.height)
        switch placement.kind {
        case .single:
            primary.place(at: origin, proposal: ProposedViewSize(bounds.size))
            secondary.place(at: origin, proposal: .zero)
        case .sideBySide:
            let trailingX = min(lead + placement.gap, bounds.width)
            primary.place(at: origin, proposal: ProposedViewSize(width: lead, height: bounds.height))
            secondary.place(
                at: CGPoint(x: origin.x + trailingX, y: origin.y),
                proposal: ProposedViewSize(width: bounds.width - trailingX, height: bounds.height)
            )
        case .stacked:
            let lowerY = min(lead + placement.gap, bounds.height)
            primary.place(at: origin, proposal: ProposedViewSize(width: bounds.width, height: lead))
            secondary.place(
                at: CGPoint(x: origin.x, y: origin.y + lowerY),
                proposal: ProposedViewSize(width: bounds.width, height: bounds.height - lowerY)
            )
        case .bench:
            let lowerY = min(lead + placement.gap, bounds.height)
            var secondaryY = origin.y
            if subviews.count > 2 {
                let header = subviews[2]
                let height = min(header.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height, lead)
                header.place(at: origin, proposal: ProposedViewSize(width: bounds.width, height: height))
                secondaryY += height
            }
            secondary.place(
                at: CGPoint(x: origin.x, y: secondaryY),
                proposal: ProposedViewSize(width: bounds.width, height: max(0, origin.y + lead - secondaryY))
            )
            primary.place(
                at: CGPoint(x: origin.x, y: origin.y + lowerY),
                proposal: ProposedViewSize(width: bounds.width, height: bounds.height - lowerY)
            )
        }
    }
}

/// A compact rest countdown for the top of the exercise pane in bench mode: the draining arc, "Rest" and the remaining time.
/// Nothing while no rest runs. Reads the engine's `RestTimer` (the same state the toolbar ring and sheet show).
struct RestCountdownHeader: View {
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    @ScaledMetric(relativeTo: .title2) private var arcSize: CGFloat = 28

    var body: some View {
        if let timer = engine?.restTimer, let endsAt = timer.endsAt, let total = timer.total {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                let remaining = max(0, endsAt.timeIntervalSince(now))
                let tint: Color = remaining <= 0 ? .ok : .accentColor
                HStack(spacing: 12) {
                    RestArc.image(
                        fraction: min(1, remaining / Double(max(1, total))),
                        size: arcSize,
                        label: Text("Rest timer"),
                        tint: tint
                    )
                    Text("Rest")
                        .font(.headline)
                    Spacer(minLength: 0)
                    Text(timerInterval: min(now, endsAt)...endsAt, countsDown: true)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rest remaining")
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityValue(
                    "\(ElapsedFormat.string(seconds: Int(remaining.rounded(.up)))) of \(ElapsedFormat.string(seconds: total))"
                )
                .accessibilityIdentifier("bench.rest")
            }
        }
    }
}
