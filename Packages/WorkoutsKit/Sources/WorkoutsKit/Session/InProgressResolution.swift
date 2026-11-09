import Foundation

/// What `ActiveWorkoutEngine.resume()` does with in-progress workouts when more than one exists (two devices that each
/// started a workout before CloudKit merged them, review C-11 c). A workout updated within the last `staleAfter` (6 h)
/// is live, being logged on another device right now; the newest-started live one is kept (the newest-started overall
/// when none is live) and any other live one is left running. Every stale one is settled by the same rule the importer
/// applies to a demoted unfinished workout (C-01, `Importer.finishedAtForDemoted`): it ends at its latest completed
/// set, else at its start. A workout with no completed set has nothing to keep and is deleted, as
/// `ActiveWorkoutEngine.finish` refuses to finish one (`nothingLogged`).
public nonisolated enum InProgressResolution {
    /// The values of one in-progress workout the rule needs.
    public struct Candidate: Sendable, Equatable {
        public var id: UUID
        public var startedAt: Date
        /// `Workout.updatedAt`: the last time any device touched the workout.
        public var updatedAt: Date
        /// `completedAt` of every completed set (nil when a completed set carries no time).
        public var completedSets: [Date?]

        public init(id: UUID, startedAt: Date, updatedAt: Date, completedSets: [Date?]) {
            self.id = id
            self.startedAt = startedAt
            self.updatedAt = updatedAt
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
        /// Stale workouts other than `keep`, newest first. A live workout that is not `keep` is in neither place.
        public var settled: [Settlement]
    }

    /// Keeps the newest-started live candidate (`updatedAt` within `staleAfter` of `now`; the newest-started overall when
    /// none is live; ties broken by id, so every device picks the same one) and settles the stale rest. Other live
    /// candidates are left alone.
    public static func plan(
        for candidates: [Candidate],
        now: Date,
        staleAfter: Duration = .seconds(6 * 3600)
    ) -> Plan {
        let ordered = candidates.sorted { ($0.startedAt, $0.id.uuidString) > ($1.startedAt, $1.id.uuidString) }
        let window = Double(staleAfter.components.seconds)
        let isLive: (Candidate) -> Bool = { now.timeIntervalSince($0.updatedAt) <= window }
        guard let kept = ordered.first(where: isLive) ?? ordered.first else { return Plan(keep: nil, settled: []) }
        let settled = ordered.filter { $0.id != kept.id && !isLive($0) }.map { candidate in
            Settlement(id: candidate.id, action: action(for: candidate))
        }
        return Plan(keep: kept.id, settled: settled)
    }

    /// Delete when no set is completed, else finish at the latest completed set (clamped to the start; the start
    /// when no completed set has a time).
    static func action(for candidate: Candidate) -> Action {
        guard !candidate.completedSets.isEmpty else { return .delete }
        let latest = candidate.completedSets.compactMap { $0 }.max()
        return .finish(at: max(latest ?? candidate.startedAt, candidate.startedAt))
    }
}
