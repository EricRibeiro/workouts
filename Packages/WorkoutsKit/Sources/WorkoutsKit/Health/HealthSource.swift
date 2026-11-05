import Foundation

/// Why Health could not be read.
public nonisolated enum HealthSourceError: Error, Equatable, Sendable {
    /// Health data is not available on this device (iPad, Mac, restricted).
    case unavailable
    /// The person has not granted (or has revoked) read access.
    case notAuthorized
    /// The candidate's details could not be found (deleted since it was listed).
    case notFound
    /// Anything else, with a message for diagnostics.
    case failed(String)
}

/// Read-only access to Apple Health. The app target implements it with HealthKit; the kit and tests use `FakeHealthSource`.
public nonisolated protocol HealthSource: Sendable {
    /// Workouts whose time range intersects `interval`. May include non-strength kinds.
    func workouts(in interval: DateInterval) async throws -> [HealthWorkoutCandidate]
    /// Energy and heart-rate details for a candidate returned by `workouts(in:)`.
    func summary(for candidate: HealthWorkoutCandidate) async throws -> HealthWorkoutSummary
}

/// An in-memory `HealthSource` for tests, previews and the app's `-healthFixture` launch argument.
public nonisolated struct FakeHealthSource: HealthSource {
    public var candidates: [HealthWorkoutCandidate]
    /// Summaries keyed by `HealthWorkoutSummary.healthWorkoutID` (matches `HealthWorkoutCandidate.id`).
    public var summaries: [String: HealthWorkoutSummary]
    /// When set, both calls throw it.
    public var error: HealthSourceError?
    /// Simulated latency before each call answers.
    public var delay: Duration?

    public init(
        candidates: [HealthWorkoutCandidate] = [],
        summaries: [HealthWorkoutSummary] = [],
        error: HealthSourceError? = nil,
        delay: Duration? = nil
    ) {
        self.candidates = candidates
        self.summaries = Dictionary(
            summaries.map { ($0.healthWorkoutID, $0) },
            uniquingKeysWith: { _, last in last }
        )
        self.error = error
        self.delay = delay
    }

    /// A source whose every call throws `error`.
    public static func failing(_ error: HealthSourceError) -> FakeHealthSource {
        FakeHealthSource(error: error)
    }

    public func workouts(in interval: DateInterval) async throws -> [HealthWorkoutCandidate] {
        try await simulate()
        return candidates.filter { $0.end >= interval.start && $0.start <= interval.end }
    }

    public func summary(for candidate: HealthWorkoutCandidate) async throws -> HealthWorkoutSummary {
        try await simulate()
        guard let summary = summaries[candidate.id] else { throw HealthSourceError.notFound }
        return summary
    }

    private func simulate() async throws {
        if let delay { try await Task.sleep(for: delay) }
        if let error { throw error }
    }
}
