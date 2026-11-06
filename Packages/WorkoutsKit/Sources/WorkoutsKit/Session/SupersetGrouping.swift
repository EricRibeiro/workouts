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

    /// The groups after a drag reorder. `old` is the list before (supersets contiguous), `newOrder` the ids after. A
    /// superset whose members are no longer next to each other is split by the move: the moved member leaves it (the
    /// member whose removal leaves every other row in its old relative order; when several moved, only the longest run
    /// of neighbours, earliest on a tie, stays), exactly like "remove from superset". Groups left with one member dissolve and
    /// the rest renumber 1, 2, 3 by first appearance. The result is in `newOrder`; ids missing from `old` are dropped.
    public static func reordered<ID: Hashable>(
        _ old: [(id: ID, group: Int?)],
        to newOrder: [ID]
    ) -> [(id: ID, group: Int?)] {
        let byID = Dictionary(old.map { ($0.id, $0.group) }, uniquingKeysWith: { first, _ in first })
        var items = newOrder.compactMap { id in byID[id].map { (id: id, group: $0) } }
        let oldIDs = old.map(\.id)
        for group in Set(items.compactMap(\.group)) {
            let positions = items.indices.filter { items[$0].group == group }
            guard let first = positions.first, let last = positions.last, last - first + 1 != positions.count
            else { continue }
            let members = positions.map { items[$0].id }
            // Single mover: dropping it makes old and new agree on every other row.
            let movers = members.filter { candidate in
                oldIDs.filter { $0 != candidate } == newOrder.filter { $0 != candidate }
            }
            let leaving: Set<Int>
            if movers.count == 1, let mover = movers.first, let index = items.firstIndex(where: { $0.id == mover }) {
                leaving = [index]
            } else {
                var best = (start: first, length: 0)
                var start = first
                for (offset, position) in positions.enumerated() {
                    if offset > 0, position != positions[offset - 1] + 1 { start = position }
                    let length = position - start + 1
                    if length > best.length { best = (start, length) }
                }
                leaving = Set(positions.filter { $0 < best.start || $0 >= best.start + best.length })
            }
            for index in leaving { items[index].group = nil }
        }
        return normalized(items)
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
