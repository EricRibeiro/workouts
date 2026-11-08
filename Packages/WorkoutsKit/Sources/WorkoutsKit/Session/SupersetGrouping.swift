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

    /// "Remove from superset": clears `id`'s group. A row that sat inside its group's run (a member on each side) moves
    /// to just after the run, the reorder parking rule, so the group stays contiguous; a first or last member stays put.
    /// Groups left with one member dissolve and the rest renumber 1, 2, 3 by first appearance. A row in no group (or an
    /// unknown id) only gets the dissolve and renumber pass.
    public static func removingFromGroup<ID: Hashable>(
        _ id: ID,
        in items: [(id: ID, group: Int?)]
    ) -> [(id: ID, group: Int?)] {
        guard let index = items.firstIndex(where: { $0.id == id }), let group = items[index].group
        else { return normalized(items) }
        var result = items
        result.remove(at: index)
        // The run's remaining members start at `index`; a row with a member before it too sat inside the run and goes
        // right after them. A first or last member is already outside what is left.
        var end = index
        if index > 0, result[index - 1].group == group {
            while end < result.count, result[end].group == group { end += 1 }
        }
        result.insert((id: id, group: nil), at: end)
        return normalized(result)
    }

    /// The rows after a drag reorder, in their final order. `old` is the list before (supersets contiguous), `newOrder`
    /// the ids after, `moving` the dragged ids when the caller knows them (it settles which row moved when the order
    /// alone is ambiguous, as in an adjacent swap).
    ///
    /// A superset the move splits is repaired by who moved. The single moved row is the one whose removal makes old and
    /// new agree, considering every row:
    /// - a member that left its group's run leaves the group, exactly like "remove from superset";
    /// - a non-member dropped inside a group's run is placed right after the run instead, so the group stays whole
    ///   (the returned order differs from `newOrder` then; callers must apply it).
    ///
    /// A group that was already split in `old` is not repaired by parking: the drop stands and the longest run stays.
    ///
    /// Without `moving`, an ambiguous move (several rows qualify) is read as the member leaving. When no single row
    /// explains the move, only the longest run of neighbours (earliest on a tie) stays grouped. Groups left with one
    /// member dissolve and the rest renumber 1, 2, 3 by first appearance. Ids missing from `old` are dropped.
    public static func reordered<ID: Hashable>(
        _ old: [(id: ID, group: Int?)],
        to newOrder: [ID],
        moving: [ID] = []
    ) -> [(id: ID, group: Int?)] {
        let byID = Dictionary(old.map { ($0.id, $0.group) }, uniquingKeysWith: { first, _ in first })
        var items = newOrder.compactMap { id in byID[id].map { (id: id, group: $0) } }
        let oldIDs = old.map(\.id)
        let candidates = newOrder.filter { candidate in
            oldIDs.filter { $0 != candidate } == newOrder.filter { $0 != candidate }
        }
        let hinted = moving.count == 1 ? moving.filter(candidates.contains) : []
        for group in Set(items.compactMap(\.group)).sorted() {
            let positions = items.indices.filter { items[$0].group == group }
            guard let first = positions.first, let last = positions.last, last - first + 1 != positions.count
            else { continue }
            let members = Set(positions.map { items[$0].id })
            let mover: ID?
            if let only = hinted.first {
                mover = only
            } else if candidates.count == 1 {
                mover = candidates.first
            } else {
                // Ambiguous: a member of this group leaving is the reading that predates the hint.
                let inside = Set(items[first...last].map(\.id)).subtracting(members)
                mover = candidates.first(where: members.contains) ?? candidates.first(where: inside.contains)
            }
            // Parking only repairs a run this move split: a group already split before the move (an import, a CloudKit
            // merge) takes the drop as made and the longest run below.
            let oldPositions = oldIDs.indices.filter { old[$0].group == group }
            let wasContiguous = oldPositions.last.map { $0 - oldPositions[0] + 1 == oldPositions.count } ?? false
            if let mover, members.contains(mover) {
                if let index = items.firstIndex(where: { $0.id == mover }) { items[index].group = nil }
            } else if wasContiguous, let mover, let from = items.firstIndex(where: { $0.id == mover }) {
                // A non-member sits inside the run: park it right after the run's last member.
                let row = items.remove(at: from)
                let end = items.lastIndex(where: { $0.group == group }) ?? items.endIndex - 1
                items.insert(row, at: end + 1)
            } else {
                var best = (start: first, length: 0)
                var start = first
                for (offset, position) in positions.enumerated() {
                    if offset > 0, position != positions[offset - 1] + 1 { start = position }
                    let length = position - start + 1
                    if length > best.length { best = (start, length) }
                }
                for index in positions where index < best.start || index >= best.start + best.length {
                    items[index].group = nil
                }
            }
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
