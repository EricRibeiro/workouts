#if DEBUG
    import Foundation
    import SwiftData
    import WorkoutsKit
    import SwiftUI
    import notify

    /// A UI-test seam (Debug builds, `-uiTesting` only): expires the running rest at once, so a test starts its own rest,
    /// asserts the running state, and then ends it deterministically instead of racing the wall clock (a loaded shard can
    /// take 15 s just to launch). The test process posts the Darwin notification ``name`` (`XCUIApplication.expireRestNow()`);
    /// the app sets the rest's end to now, and the real watchers then run the real over/grace/forget path.
    enum RestExpirySeam {
        static let name = "com.ericribeiro.Workouts.debug.expireRest"

        @MainActor private static var engine: ActiveWorkoutEngine?
        @MainActor private static var context: ModelContext?
        private nonisolated(unsafe) static var token: Int32 = 0

        /// Starts listening; a no-op outside `-uiTesting` and when already listening.
        @MainActor
        static func install(engine: ActiveWorkoutEngine, context: ModelContext) {
            guard ProcessInfo.processInfo.arguments.contains("-uiTesting"), token == 0 else { return }
            self.engine = engine
            self.context = context
            notify_register_dispatch(name, &token, DispatchQueue.main) { _ in
                MainActor.assumeIsolated { expire() }
            }
        }

        /// Sets the running rest's end to now (a no-op without a running rest).
        @MainActor
        private static func expire() {
            guard let workout = engine?.workout, workout.restEndsAt != nil else { return }
            workout.restEndsAt = .now
            try? context?.save()
        }
    }

    /// The read side of the seam (`-uiTesting` only): a zero-size, non-hittable accessibility element in the root overlay,
    /// above the `TabView` and so present on every pushed screen. Identifier `debug.restState`, value `none` (no rest),
    /// `running`, or `over` (expired but not yet forgotten), straight from the engine's rest timer. A test waits for
    /// `over` and then `none` on a pushed screen to prove who forgot the rest. No layout, nothing visible.
    private struct RestStateProbe: ViewModifier {
        @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?

        func body(content: Content) -> some View {
            if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                content.overlay {
                    // The rest changes state by the clock (running to over) without any observed property changing.
                    TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                        Color.clear
                            .frame(width: 0, height: 0)
                            .allowsHitTesting(false)
                            .accessibilityElement()
                            .accessibilityIdentifier("debug.restState")
                            .accessibilityLabel("Rest state")
                            .accessibilityValue(state(at: timeline.date))
                    }
                }
            } else {
                content
            }
        }

        private func state(at date: Date) -> String {
            guard let timer = engine?.restTimer, timer.isActive else { return "none" }
            return timer.isExpired(at: date) ? "over" : "running"
        }
    }

    extension View {
        /// Hosts the `debug.restState` probe (see ``RestExpirySeam``); a no-op outside `-uiTesting`.
        func restStateProbe() -> some View {
            modifier(RestStateProbe())
        }
    }
#endif
