//
//  RestRunningSheet.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The expanded rest timer (Clock's ring): remaining over total, with -10 s, +10 s and Skip as a toolbar group the system
/// places. Closes itself when the rest ends.
struct RestRunningSheet: View {
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    @Environment(SaveErrors.self) private var errors: SaveErrors?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let timer = engine?.restTimer, let endsAt = timer.endsAt, let total = timer.total {
                    ring(endsAt: endsAt, total: total)
                } else {
                    Color.clear
                }
            }
            .navigationTitle("Rest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Done")
                        .accessibilityIdentifier("rest.done")
                }
                ToolbarItemGroup {
                    Button("Minus 10 seconds", systemImage: "gobackward.10") { adjust(by: -10) }
                        .accessibilityLabel("Minus 10 seconds")
                        .accessibilityIdentifier("rest.minus10")
                    Button("Plus 10 seconds", systemImage: "goforward.10") { adjust(by: 10) }
                        .accessibilityLabel("Plus 10 seconds")
                        .accessibilityIdentifier("rest.plus10")
                    Button("Skip", systemImage: "forward.end") { skip() }
                        .accessibilityLabel("Skip rest")
                        .accessibilityIdentifier("rest.skip")
                }
            }
        }
        .onChange(of: engine?.restTimer.isActive ?? false) { _, isActive in
            if !isActive { dismiss() }
        }
        .accessibilityIdentifier("screen.restRunning")
    }

    private func ring(endsAt: Date, total: Int) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let now = context.date
            let remaining = max(0, endsAt.timeIntervalSince(now))
            ProgressView(value: remaining, total: Double(max(1, total))) {
                EmptyView()
            } currentValueLabel: {
                VStack(spacing: 4) {
                    Text(timerInterval: min(now, endsAt)...endsAt, countsDown: true)
                        .font(.largeTitle.weight(.semibold).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("of \(ClockFormat.clock(seconds: total))")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            }
            .progressViewStyle(RingProgressStyle(lineWidth: 10))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest remaining")
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityValue(
                "\(ClockFormat.clock(seconds: Int(remaining.rounded(.up)))) of \(ClockFormat.clock(seconds: total))"
            )
            .accessibilityIdentifier("rest.sheet.ring")
        }
        .padding(32)
        .frame(maxWidth: 360, maxHeight: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func adjust(by seconds: Int) {
        do {
            try engine?.adjustRest(by: seconds)
        } catch {
            errors?.report(error)
        }
    }

    private func skip() {
        do {
            try engine?.skipRest()
        } catch {
            errors?.report(error)
        }
        dismiss()
    }
}
