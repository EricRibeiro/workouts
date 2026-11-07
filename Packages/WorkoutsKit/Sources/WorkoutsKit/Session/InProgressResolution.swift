import Foundation

/// What `ActiveWorkoutEngine.resume()` does with in-progress workouts when more than one exists (two devices that each
/// started a workout before CloudKit merged them, review C-11 c). The newest start is kept; every older one is settled
/// by the same rule the importer applies to a demoted unfinished workout (C-01, `Importer.finishedAtForDemoted`): it
/// ends at its latest completed set, else at its start. A workout with no completed set has nothing to keep and is
/// deleted, as `ActiveWorkoutEngine.finish` refuses to finish one (`nothingLogged`).
public nonisolated enum InProgressResolution {
    /// The values of one in-progress workout the rule needs.
    public struct Candidate: Sendable, Equatable {
        public var id: UUID
        public var startedAt: Date
        /// `completedAt` of every completed set (nil when a completed set carries no time).
        public var completedSets: [Date?]

        public init(id: UUID, startedAt: Date, completedSets: [Date?]) {
            self.id = id
            self.startedAt = startedAt
            self.completedSets = completedSets
        }
    }

    /// What happens to an older in-progress workout.
    public enum Action: Sendable, Equatable {
        /// Nothing was logged: remove it.
        case delete
        /// Mark it finished at this time (never before its start).
        case finish(at: Date)
    }

    /// One older workout and what happens to it.
    public struct Settlement: Sendable, Equatable {
        public var id: UUID
        public var action: Action
    }

    /// The decision for a set of candidates: the workout that stays in progress and the action for each other one.
    public struct Plan: Sendable, Equatable {
        public var keep: UUID?
        /// Older workouts, newest first.
        public var settled: [Settlement]
    }

    /// Keeps the newest `startedAt` (ties broken by id, so every device picks the same one) and settles the rest.
    public static func plan(for candidates: [Candidate]) -> Plan {
        let ordered = candidates.sorted { ($0.startedAt, $0.id.uuidString) > ($1.startedAt, $1.id.uuidString) }
        guard let newest = ordered.first else { return Plan(keep: nil, settled: []) }
        let settled = ordered.dropFirst().map { candidate in
            Settlement(id: candidate.id, action: action(for: candidate))
        }
        return Plan(keep: newest.id, settled: Array(settled))
    }

    /// Delete when no set is completed, else finish at the latest completed set (clamped to the start; the start
    /// when no completed set has a time).
    static func action(for candidate: Candidate) -> Action {
        guard !candidate.completedSets.isEmpty else { return .delete }
        let latest = candidate.completedSets.compactMap { $0 }.max()
        return .finish(at: max(latest ?? candidate.startedAt, candidate.startedAt))
    }
}
