//
//  RestTimerRow.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The counting-down rest, inline under the set whose check started it: the countdown, the draining bar and Add 30 s / Skip. It is
/// not a set row (no swipe actions); it is where a set's rest is controlled, so the logging toolbar shows the ring alone.
/// The engine keeps an over rest for a few seconds (the toolbar pill flashes `0:00`); this row disappears at `endsAt` instead.
struct RestTimerRow: View {
    let rest: SetTableRest
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var touch = 44.0
    @ScaledMetric(relativeTo: .body) private var barHeight = 6.0

    var body: some View {
        // One entry at `endsAt` re-renders the gate exactly when the countdown reaches 0; +30 s swaps the schedule.
        TimelineView(.explicit([rest.endsAt])) { _ in
            if Date.now < rest.endsAt { row }
        }
    }

    private var row: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let remaining = max(0, rest.endsAt.timeIntervalSince(now))
            let fraction = rest.total > 0 ? min(1, remaining / Double(rest.total)) : 0
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(timerInterval: min(now, rest.endsAt)...rest.endsAt, countsDown: true)
                    .font(.title3.weight(.medium).monospacedDigit())
                    .fontDesign(.rounded)
                    .accessibilityLabel("Rest remaining")
                    .accessibilityValue(ClockFormat.clock(seconds: Int(remaining.rounded(.up))))
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("rest.row.countdown")
                if dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                } else {
                    Capsule()
                        .fill(.fill.quaternary)
                        .frame(height: barHeight)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(.tint)
                                    .frame(width: proxy.size.width * fraction)
                            }
                        }
                        .animation(.linear(duration: 1), value: fraction)
                        .accessibilityHidden(true)
                }
                Button(action: rest.add30) {
                    Text("+30")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: touch, minHeight: touch)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Add 30 seconds")
                .accessibilityIdentifier("rest.row.plus30")
                Button(action: rest.skip) {
                    Image(systemName: "forward.end.fill")
                        .frame(minWidth: touch, minHeight: touch)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Skip rest")
                .accessibilityIdentifier("rest.row.skip")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: touch)
        .background(.fill.secondary, in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rest.row")
        .padding(.vertical, 2)
    }
}
