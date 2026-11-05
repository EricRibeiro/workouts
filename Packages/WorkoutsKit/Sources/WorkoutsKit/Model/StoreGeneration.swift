import Foundation
import Observation
import SwiftData

/// A counter that screens fold into the key of their derived caches (`.task(id:)`), for the changes the newest
/// `updatedAt` cannot see: a bulk write that updates an older finished workout (a JSON import of a corrected export,
/// later a CloudKit push from another device, PLAN 8.1) or removes one that is not the newest. The writer calls
/// ``bump()`` once after the write succeeded; every view that read ``value`` while building its key re-derives.
///
/// Why a counter and not `ModelContext.didSave`: the notification fires on every save, including each set check-off
/// and keystroke of the logging screen (every cache would recompute per save), says nothing about which entities
/// changed, and is not a documented signal for changes the CloudKit mirror merges in. The explicit bump costs one line at
/// each bulk-write site and recomputes exactly once per such write.
@Observable
public final class StoreGeneration {
    /// Starts at 0 and only grows.
    public private(set) var value = 0

    public init() {}

    /// Marks that finished workouts changed in a way their `updatedAt` stamps do not show.
    public func bump() {
        value += 1
    }
}

/// The key of a cache derived from the finished workouts, built without reading any of them: the newest `updatedAt`
/// among them (every editor stamps it: `PastWorkoutDraft.apply`, the engine's finish) plus the ``StoreGeneration``.
public struct FinishedWorkoutsStamp: Hashable, Sendable {
    public let newestEdit: Date?
    public let generation: Int

    public init(newestEdit: Date?, generation: Int) {
        self.newestEdit = newestEdit
        self.generation = generation
    }
}

extension Workout {
    /// The finished workout edited last (`fetchLimit` 1): with ``FinishedWorkoutsStamp`` it keys a cache without a query
    /// that faults every finished workout.
    public static var newestFinishedEdit: FetchDescriptor<Workout> {
        var descriptor = FetchDescriptor<Workout>(
            predicate: finishedPredicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// The finished workout `id`, for `Query(_:)`: zero or one row.
    public static func finished(id: UUID) -> FetchDescriptor<Workout> {
        var descriptor = FetchDescriptor<Workout>(
            predicate: finishedPredicate(id: id)
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// Every finished workout, for a one-shot `context.fetch` inside a derivation task (not an observed `@Query`).
    public static var allFinished: FetchDescriptor<Workout> {
        FetchDescriptor<Workout>(predicate: finishedPredicate)
    }
}
