//
//  RestRingItem.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The rest timer's toolbar item (task 2.5). Idle: a stopwatch `Menu` of presets, saved customs and "Custom…". Running:
/// a button whose label is the countdown ring; tapping it opens ``RestRunningSheet``.
///
/// Reads the engine from the environment. The countdown is `Text(timerInterval:)` from the persisted end date; a
/// once-a-second `TimelineView` feeds the ring's arc, and one sleep until the end date fires the haptic and forgets the rest.
struct RestRingItem: View {
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    @Environment(SaveErrors.self) private var errors: SaveErrors?
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @State private var isCustomPresented = false
    @State private var isRunningPresented = false
    /// Bumped once when a rest reaches 0 while this view watches; drives the success haptic.
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
            let customs = settings?.restPresets ?? SettingsStore.restPresetsDefault
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
        return Button(text, systemImage: "timer") { start(seconds, engine: engine) }
            .accessibilityLabel("Rest \(text)")
            .accessibilityIdentifier("rest.preset.\(seconds)")
    }

    private func start(_ seconds: Int, engine: ActiveWorkoutEngine) {
        do {
            try engine.startRest(seconds: seconds)
        } catch {
            errors?.report(error)
        }
    }

    private func runningButton(engine: ActiveWorkoutEngine, endsAt: Date, total: Int) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            let fraction = min(1, remaining / Double(max(1, total)))
            let time = ElapsedFormat.string(seconds: Int(remaining.rounded(.up)))
            // An over rest stays in the engine for ``RestTimer/expiredGraceSeconds``: the arc is ok-coloured meanwhile.
            let tint: Color? = remaining <= 0 ? .ok : nil
            Button {
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
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("rest.ring")
        }
        .sheet(isPresented: $isRunningPresented) {
            RestRunningSheet()
                .presentationPlacement(.trailing)
                .presentationDetents([.medium])
        }
        // The engine keeps an over rest for a few seconds (the flash); nothing else forgets it afterwards.
        .sensoryFeedback(.success, trigger: restEndCount)
        .task(id: endsAt) {
            await engine.awaitRestExpiry(endsAt: endsAt) { restEndCount += 1 }
        }
    }

    private func arcImage(fraction: Double, tint: Color?) -> Image {
        RestArc.image(fraction: fraction, size: arcSize, label: Text("Rest timer"), tint: tint)
    }
}

extension ActiveWorkoutEngine {
    /// Sleeps until the rest ending at `endsAt` is over, runs `onEnded` once (the success haptic), then sleeps through
    /// ``RestTimer/expiredGraceSeconds`` and forgets the rest with ``tickRest()``. Two sleeps on the persisted end date,
    /// not a per-second poll. A rest that is already over when this starts does not call `onEnded` (relaunch must not
    /// buzz). Returns early when cancelled (the rest changed or the view went away).
    func awaitRestExpiry(endsAt: Date, onEnded: () -> Void) async {
        if endsAt > .now {
            guard await Self.sleep(until: endsAt) else { return }
            onEnded()
        }
        let forgetAt = endsAt.addingTimeInterval(TimeInterval(RestTimer.expiredGraceSeconds))
        while true {
            guard await Self.sleep(until: forgetAt) else { return }
            // A failed save while forgetting an over rest is harmless: retry once a second (no alert, it would repeat).
            if (try? tickRest()) == true { return }
            guard await Self.sleep(until: max(forgetAt, .now.addingTimeInterval(1))) else { return }
        }
    }

    /// `Task.sleep` until a wall-clock date, re-checking the date after waking. False when cancelled.
    private static func sleep(until date: Date) async -> Bool {
        let clock = ContinuousClock()
        while date.timeIntervalSinceNow > 0 {
            do {
                try await Task.sleep(until: clock.now.advanced(by: .seconds(date.timeIntervalSinceNow)), clock: clock)
            } catch {
                return false
            }
        }
        return !Task.isCancelled
    }
}
