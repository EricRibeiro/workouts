//
//  WorkoutLinkRouter.swift
//  Workouts
//

import Observation

/// Carries "show the running workout" from outside the view tree (a tap on the rest notification's body) to `RootView`,
/// which owns the navigation state. A request made before the root view exists (a cold launch from the notification)
/// stays pending until it appears.
@MainActor
@Observable
final class WorkoutLinkRouter {
    private(set) var isPending = false

    func request() { isPending = true }

    /// Returns whether a request was waiting, and clears it.
    func consume() -> Bool {
        defer { isPending = false }
        return isPending
    }
}
