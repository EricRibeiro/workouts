//
//  EngineActivityIntentHandler.swift
//  Workouts
//

import Foundation
import WorkoutsKit

/// The app side of the Live Activity buttons: applies Skip / +30 s / Done set to the one engine. An intent can arrive
/// while the process has only just been launched in the background, so every action first resumes the persisted
/// workout when the engine has none.
@MainActor
final class EngineActivityIntentHandler: ActivityIntentHandling {
    private let engine: ActiveWorkoutEngine

    init(engine: ActiveWorkoutEngine) {
        self.engine = engine
    }

    func skipRest() throws {
        try resumeIfNeeded()
        try engine.skipRest()
    }

    func addRest(seconds: Int) throws {
        try resumeIfNeeded()
        try engine.adjustRest(by: seconds)
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
