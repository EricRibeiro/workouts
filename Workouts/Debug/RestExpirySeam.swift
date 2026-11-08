#if DEBUG
    import Foundation
    import SwiftData
    import WorkoutsKit
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
#endif
