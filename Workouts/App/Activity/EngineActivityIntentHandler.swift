//
//  EngineActivityIntentHandler.swift
//  Workouts
//

import Foundation
import WorkoutsKit

/// The app side of the Live Activity buttons: applies Skip / +30 s / Done set to the one engine. An intent can arrive
/// while the process has only just been launched in the background, so every action first resumes the persisted
/// workout when the engine has none. After each action ``flush()`` brings the Live Activity and the rest notification
/// up to date immediately instead of waiting for their debounced observers, which may never run in a suspended app.
@MainActor
final class EngineActivityIntentHandler: ActivityIntentHandling {
    private let engine: ActiveWorkoutEngine
    private let activityController: LiveActivityController?
    private let notifier: RestNotifier?

    init(
        engine: ActiveWorkoutEngine,
        activityController: LiveActivityController? = nil,
        notifier: RestNotifier? = nil
    ) {
        self.engine = engine
        self.activityController = activityController
        self.notifier = notifier
    }

    func flush() async {
        await notifier?.syncNow()
        await activityController?.syncNow()
    }

    func skipRest() throws {
        try resumeIfNeeded()
        try engine.skipRest()
    }

    func addRest(seconds: Int) throws {
        try resumeIfNeeded()
        try engine.extendOrRestartRest(by: seconds)
    }

    func completeSet(id: UUID) throws {
        try resumeIfNeeded()
        let sets = (engine.workout?.exercises ?? []).flatMap { $0.sets ?? [] }
        guard let set = sets.first(where: { $0.id == id }) else { return }
        try engine.check(set)
    }

    private func resumeIfNeeded() throws {
        if engine.workout == nil { try engine.resume() }
    }
}
