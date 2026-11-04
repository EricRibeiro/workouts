//
//  RestRingItem.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The rest timer's toolbar item (task 2.5). Idle: a stopwatch `Menu` of presets, saved customs and "Custom…". Running:
/// a button whose label is the countdown ring; tapping it opens ``RestRunningSheet``.
///
/// Reads the engine from the environment. The countdown is `Text(timerInterval:)` from the persisted end date; the
/// `TimelineView` only feeds the ring's arc.
struct RestRingItem: View {
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    @State private var isCustomPresented = false
    @State private var isRunningPresented = false
    /// Updated by the 1 s rest loop; the arc and the accessibility time derive from it.
    @State private var now = Date.now
    /// Bumped by the 1 s loop when a rest reaches 0 while this view watches; drives the success haptic.
    @State private var restEndCount = 0
    @ScaledMetric(relativeTo: .body) private var arcSize: CGFloat = 22

    var body: some View {
        Group {
            if let engine {
                let timer = engine.restTimer
                if let endsAt = timer.endsAt, let total = timer.total {
                    runningButton(engine: engine, endsAt: endsAt, total: total)
                } else {
                    idleMenu(engine: engine)
                }
            }
        }
    }

    private func idleMenu(engine: ActiveWorkoutEngine) -> some View {
        Menu {
            ForEach(RestTimer.defaultPresets, id: \.self) { seconds in
                presetButton(seconds, engine: engine)
            }
            let customs = SettingsStore().restPresets
            if !customs.isEmpty {
                Divider()
                ForEach(customs, id: \.self) { seconds in
                    presetButton(seconds, engine: engine)
                }
            }
            Divider()
            Button("Custom…", systemImage: "slider.horizontal.3") { isCustomPresented = true }
                .accessibilityLabel("Custom rest timer")
                .accessibilityIdentifier("rest.custom")
        } label: {
            Label("Rest timer", systemImage: "stopwatch")
        }
        .accessibilityLabel("Rest timer")
        .accessibilityIdentifier("rest.ring")
        .sheet(isPresented: $isCustomPresented) {
            RestCustomSheet()
                .presentationPlacement(.center)
        }
    }

    private func presetButton(_ seconds: Int, engine: ActiveWorkoutEngine) -> some View {
        let text = ElapsedFormat.string(seconds: seconds)
        return Button(text, systemImage: "timer") { try? engine.startRest(seconds: seconds) }
            .accessibilityLabel("Rest \(text)")
            .accessibilityIdentifier("rest.preset.\(seconds)")
    }

    private func runningButton(engine: ActiveWorkoutEngine, endsAt: Date, total: Int) -> some View {
        let remaining = max(0, endsAt.timeIntervalSince(now))
        let fraction = min(1, remaining / Double(max(1, total)))
        let time = ElapsedFormat.string(seconds: Int(remaining.rounded(.up)))
        // An over rest stays in the engine for ``RestTimer/expiredGraceSeconds``: the arc is ok-coloured meanwhile.
        let tint: Color? = remaining <= 0 ? .ok : nil
        return Button {
            isRunningPresented = true
        } label: {
            // A Label with an Image icon is what the closed Duo moves into the trailing strip; a custom view is not.
            Label {
                Text("Rest timer")
            } icon: {
                arcImage(fraction: fraction, tint: tint)
            }
        }
        // The strip drops accessibilityValue, so the remaining time rides in the label.
        .accessibilityLabel("Rest timer, \(time)")
        .accessibilityIdentifier("rest.ring")
        .sheet(isPresented: $isRunningPresented) {
            RestRunningSheet()
                .presentationPlacement(.trailing)
                .presentationDetents([.medium])
        }
        // The engine keeps an over rest for a few seconds (the flash); nothing else forgets it afterwards.
        .sensoryFeedback(.success, trigger: restEndCount)
        .task(id: endsAt) {
            now = .now
            // A rest already over when this view appears (relaunch) must not buzz.
            var hasEnded = endsAt <= now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
                if !hasEnded, endsAt <= now {
                    hasEnded = true
                    restEndCount += 1
                }
                if (try? engine.tickRest()) == true { break }
            }
        }
    }

    private func arcImage(fraction: Double, tint: Color?) -> Image {
        RestArc.image(fraction: fraction, size: arcSize, label: Text("Rest timer"), tint: tint)
    }
}
