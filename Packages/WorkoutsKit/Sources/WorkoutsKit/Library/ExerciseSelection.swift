import Foundation

/// The ticked exercises of a multi-select picker, in the order they were ticked.
///
/// Ids rather than `ExerciseInfo` values, so a search or filter that hides a ticked row never drops it; `resolve(_:)`
/// turns the ids back into exercises in tick order.
public nonisolated struct ExerciseSelection: Sendable, Hashable {
    /// A superset needs at least this many exercises.
    public static let supersetMinimum = 2

    /// Ticked ids, oldest tick first.
    public private(set) var ids: [UUID]

    public init(ids: [UUID] = []) {
        var seen = Set<UUID>()
        self.ids = ids.filter { seen.insert($0).inserted }
    }

    public var count: Int { ids.count }

    /// Add (N) is enabled once anything is ticked.
    public var canAdd: Bool { !ids.isEmpty }

    /// Superset is enabled once at least `supersetMinimum` exercises are ticked.
    public var canSuperset: Bool { ids.count >= Self.supersetMinimum }

    public func contains(_ id: UUID) -> Bool {
        ids.contains(id)
    }

    /// Unticks `id` when ticked, otherwise ticks it last. Returns whether `id` is ticked afterwards.
    @discardableResult
    public mutating func toggle(_ id: UUID) -> Bool {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
            return false
        }
        ids.append(id)
        return true
    }

    /// Ticks `id` last unless it is already ticked (the saved exercise of "New" is auto-ticked this way).
    public mutating func select(_ id: UUID) {
        if !contains(id) { ids.append(id) }
    }

    public mutating func clear() {
        ids.removeAll()
    }

    /// The ticked exercises in tick order; ids `lookup` no longer knows are skipped.
    public func resolve(_ lookup: (UUID) -> ExerciseInfo?) -> [ExerciseInfo] {
        ids.compactMap(lookup)
    }
}
