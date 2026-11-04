/// Superset bookkeeping over an ordered list of `(id, group)` (`workout.md` section 3, "Supersets"). Pure: the engine
/// applies the result to the workout's exercises.
public nonisolated enum SupersetGrouping {
    /// Makes `members` one superset: they are gathered next to each other at the first member's position (relative
    /// order kept), take a fresh group, groups left with fewer than two members dissolve to nil, and groups are
    /// renumbered 1, 2, 3 by first appearance. Ids in `members` that are not in `items` are ignored; with fewer than
    /// two present members nothing is grouped and the list only gets the dissolve and renumber pass.
    public static func grouping<ID: Hashable>(
        _ items: [(id: ID, group: Int?)],
        members: [ID]
    ) -> [(id: ID, group: Int?)] {
        let wanted = Set(members)
        let present = items.filter { wanted.contains($0.id) }
        guard present.count >= 2 else { return normalized(items) }
        let fresh = (items.compactMap(\.group).max() ?? 0) + 1
        var result: [(id: ID, group: Int?)] = []
        var gathered = false
        for item in items {
            if wanted.contains(item.id) {
                guard !gathered else { continue }
                gathered = true
                result.append(contentsOf: present.map { (id: $0.id, group: fresh) })
            } else {
                result.append(item)
            }
        }
        return normalized(result)
    }

    /// Drops `id`; a superset left with one member dissolves (removing one of a pair frees the other). Groups are
    /// renumbered 1, 2, 3 by first appearance.
    public static func removing<ID: Hashable>(
        _ id: ID,
        from items: [(id: ID, group: Int?)]
    ) -> [(id: ID, group: Int?)] {
        normalized(items.filter { $0.id != id })
    }

    /// Dissolves groups with fewer than two members and renumbers the rest 1, 2, 3 by first appearance.
    static func normalized<ID: Hashable>(_ items: [(id: ID, group: Int?)]) -> [(id: ID, group: Int?)] {
        var counts: [Int: Int] = [:]
        for case let group? in items.map(\.group) { counts[group, default: 0] += 1 }
        var numbers: [Int: Int] = [:]
        return items.map { item in
            guard let group = item.group, counts[group, default: 0] >= 2 else { return (id: item.id, group: nil) }
            if let known = numbers[group] { return (id: item.id, group: known) }
            let number = numbers.count + 1
            numbers[group] = number
            return (id: item.id, group: number)
        }
    }
}
