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
/// once-a-second `TimelineView` feeds the ring's arc. It only draws: the cover's ``RestExpiryWatcher`` fires the haptic
/// and forgets the rest, because this item leaves the toolbar while a set field has focus.
struct RestRingItem: View {
    private enum RestSheet: String, Identifiable {
        case running, custom
        var id: String { rawValue }
    }

    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    @Environment(SaveErrors.self) private var errors: SaveErrors?
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    /// The sheet being shown. One enum-driven presenter on the stable container, because the idle menu and the running
    /// button replace each other and a presenter that leaves with its sheet open never gets the sheet's own reset.
    @State private var sheet: RestSheet?
    @ScaledMetric(relativeTo: .body) private var arcSize: CGFloat = 22

    var body: some View {
        ZStack {
            if let engine {
                let timer = engine.restTimer
                if let endsAt = timer.endsAt, let total = timer.total {
                    runningButton(engine: engine, endsAt: endsAt, total: total)
                } else {
                    idleMenu(engine: engine)
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .running:
                RestRunningSheet()
                    .presentationPlacement(.trailing)
                    .presentationDetents([.medium])
            case .custom:
                RestCustomSheet()
                    .presentationPlacement(.center)
            }
        }
        // The custom sheet starts a rest and the running sheet ends with it: either way the sheet is done once the rest
        // flips state, and a stale value would reopen it at the next rest.
        .onChange(of: engine?.restTimer.endsAt == nil) {
            sheet = nil
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
            Button("Custom…", systemImage: "slider.horizontal.3") { sheet = .custom }
                .accessibilityLabel("Custom rest timer")
                .accessibilityIdentifier("rest.custom")
        } label: {
            Label("Rest timer", systemImage: "stopwatch")
        }
        .accessibilityLabel("Rest timer")
        .accessibilityIdentifier("rest.ring")
    }

    private func presetButton(_ seconds: Int, engine: ActiveWorkoutEngine) -> some View {
        let text = ClockFormat.clock(seconds: seconds)
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
            // An over rest stays in the engine for ``RestTimer/expiredGraceSeconds``: the arc is ok-coloured meanwhile, accent-coloured while it runs.
            let tint: Color = remaining <= 0 ? .ok : .accentColor
            Button {
                sheet = .running
            } label: {
                // A Label with an Image icon is what the closed Duo moves into the trailing strip; a custom view is not.
                Label {
                    Text("Rest timer")
                } icon: {
                    arcImage(fraction: fraction, tint: tint, isOver: remaining <= 0)
                }
            }
            // The strip drops accessibilityValue, so the remaining time rides in the label ("Rest over" in the grace).
            .accessibilityLabel(RestAccessibility.ringLabel(remaining: remaining))
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("rest.ring")
        }
    }

    /// A bare draining arc while the rest runs (it sits next to other logging controls); a checkmark once it is over.
    private func arcImage(fraction: Double, tint: Color?, isOver: Bool) -> Image {
        RestArc.image(
            fraction: fraction,
            size: arcSize,
            label: Text("Rest timer"),
            tint: tint,
            glyph: isOver ? "checkmark" : nil
        )
    }
}
