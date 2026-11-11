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
/// The two views meet at the hinge in every open pose, as the system's `.split.axes(axes)` does for an active division, measured
/// on the Duo (6.2): with the Duo half-open the split follows the division region, so each view sits entirely on its own side of
/// the fold (book: primary left, pane right). Flat open, the hinge is an inactive division and the views meet on it the same
/// way (side by side on a vertical one, stacked on a horizontal one): the area excludes the system's bar strip, so its centre is
/// not the hinge. With no division at all the two halves are equal (side by side when the area is wider than tall, primary above
/// secondary otherwise).
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
        var foldAxes: FoldPlacement.Axes = []
        if axes.contains(.horizontal) { foldAxes.insert(.horizontal) }
        if axes.contains(.vertical) { foldAxes.insert(.vertical) }
        let regions = proxy.reservedRegions(kind: .division, options: .includeInactive)
        return FoldPlacement.placement(
            size: proxy.size,
            divisions: regions.filter(\.isActive).map(\.frame),
            inactiveDivisions: regions.filter { !$0.isActive }.map(\.frame),
            axes: foldAxes
        )
    }
}

/// Places the primary, the secondary and, in bench mode, the rest header (subviews in that order, the header last), at the
/// frames `FoldPlacement` decides.
private struct BenchLayout: Layout {
    typealias Placement = FoldPlacement.Placement

    var placement: Placement

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 2 else { return }
        let header = subviews.count > 2 && placement.isBench ? subviews[2] : nil
        let headerHeight = header?.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
        let frames = FoldPlacement.frames(for: placement, in: bounds, headerHeight: headerHeight)
        subviews[0].place(at: frames.primary.origin, proposal: ProposedViewSize(frames.primary.size))
        subviews[1].place(at: frames.secondary.origin, proposal: ProposedViewSize(frames.secondary.size))
        if let header, let frame = frames.header {
            header.place(at: frame.origin, proposal: ProposedViewSize(frame.size))
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
                    "\(ClockFormat.clock(seconds: Int(remaining.rounded(.up)))) of \(ClockFormat.clock(seconds: total))"
                )
                .accessibilityIdentifier("bench.rest")
            }
        }
    }
}
