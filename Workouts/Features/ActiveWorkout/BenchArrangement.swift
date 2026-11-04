//
//  BenchArrangement.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The logging screen's arrangement style (task 6.1). Everywhere except the half-open laptop pose it is exactly the system
/// split (`.split.axes(axes)`), so closed and fully open look and behave as before. When the Duo is half-open with the hinge
/// across the display (an active division region wider than tall, "bench mode") the system split would put the primary on
/// the upper half; this puts the secondary (the exercise pane, with the rest countdown above it while a rest runs) on the
/// upper half and the primary (the set table) on the lower, each entirely on its own side of the division.
///
/// The primary and secondary are the style configuration's placeholders in both branches, so the content stays hosted by the
/// `ArrangementView` and a fold does not recreate the set table.
struct BenchArrangementStyle: ArrangementViewStyle {
    var axes: Axis.Set

    func makeBody(configuration: Configuration) -> some View {
        BenchArrangementBody(configuration: configuration, axes: axes)
    }
}

private struct BenchArrangementBody: View {
    let configuration: ArrangementViewStyleConfiguration
    let axes: Axis.Set

    var body: some View {
        GeometryReader { proxy in
            if let division = benchDivision(in: proxy) {
                bench(division: division, size: proxy.size)
            } else {
                ArrangementView(configuration)
                    .arrangementViewStyle(.split.axes(axes))
            }
        }
    }

    /// The active division region when it lies across the display (wider than tall: laptop, not book) and the arrangement
    /// may stack; otherwise nil.
    private func benchDivision(in proxy: GeometryProxy) -> ReservedRegion? {
        guard axes.contains(.vertical) else { return nil }
        return proxy.reservedRegions(kind: .division)
            .first { $0.isActive && $0.frame.width > $0.frame.height }
    }

    private func bench(division: ReservedRegion, size: CGSize) -> some View {
        let upper = max(0, division.frame.minY)
        let gap = division.frame.height
        let lower = max(0, size.height - upper - gap)
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                RestCountdownHeader()
                configuration.secondary
            }
            .frame(height: upper)
            Color.clear.frame(height: gap)
            configuration.primary
                .frame(height: lower)
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
                let tint: Color? = remaining <= 0 ? .ok : nil
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
                .accessibilityValue(
                    "\(ElapsedFormat.string(seconds: Int(remaining.rounded(.up)))) of \(ElapsedFormat.string(seconds: total))"
                )
                .accessibilityIdentifier("bench.rest")
            }
        }
    }
}
