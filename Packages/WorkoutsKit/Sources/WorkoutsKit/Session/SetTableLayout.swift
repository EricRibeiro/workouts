import Foundation

/// Pure rules behind the set table's exercise blocks (task 2.3): superset numbering, the rest caption and the result of a
/// block drag. The view applies them; the tests live here.
public nonisolated enum SetTableLayout {
    /// The display number of each exercise's superset: groups are renumbered 1, 2, 3 in order of first appearance
    /// (`workout.md` "Supersets", `data-model.md` section 1), whatever raw group values the model holds. nil stays nil.
    /// A group with a single member is meaningless and is shown as no superset.
    public static func supersetNumbers(for groups: [Int?]) -> [Int?] {
        var counts: [Int: Int] = [:]
        for case let group? in groups { counts[group, default: 0] += 1 }
        var numbers: [Int: Int] = [:]
        return groups.map { group in
            guard let group, counts[group, default: 0] >= 2 else { return nil }
            if let known = numbers[group] { return known }
            let number = numbers.count + 1
            numbers[group] = number
            return number
        }
    }

    /// The rest caption under an exercise name: `Rest 2:00`, `Rest 0:30`; nil when rest is off (0 or none).
    public static func restCaption(seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        return "Rest \(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    /// `order` after moving `moving` (kept in their current relative order) to just before `destination`, or to the end
    /// when `destination` is nil or is itself being moved. Ids not in `order` are ignored.
    public static func reordered<ID: Hashable>(_ order: [ID], moving: [ID], before destination: ID?) -> [ID] {
        let moved = Set(moving)
        let carried = order.filter { moved.contains($0) }
        guard !carried.isEmpty else { return order }
        var rest = order.filter { !moved.contains($0) }
        let index = destination.flatMap { rest.firstIndex(of: $0) } ?? rest.endIndex
        rest.insert(contentsOf: carried, at: index)
        return rest
    }
}
