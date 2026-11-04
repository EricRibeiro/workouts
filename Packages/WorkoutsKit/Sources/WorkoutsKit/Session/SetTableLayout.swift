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

    /// The rest caption under an exercise name: `Rest 2:00` for its own length, `Rest 1:30 (default)` for nil (Default, the
    /// Settings value `defaultSeconds`), `Rest off` for 0 (or a default of 0).
    public static func restCaption(seconds: Int?, defaultSeconds: Int) -> String {
        guard let seconds else {
            return defaultSeconds > 0 ? "Rest \(clock(defaultSeconds)) (default)" : "Rest off"
        }
        return seconds > 0 ? "Rest \(clock(seconds))" : "Rest off"
    }

    private static func clock(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
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

    /// The exercise the logging screen's pane shows when nothing was focused or tapped yet (`DECISIONS.md` "Active
    /// workout"): the first block with an unchecked set. When every set is checked (or no block has sets) it is the first
    /// block, so the pane never goes blank while a workout has exercises; nil only when there are none.
    public static func defaultFocusedSection<ID>(sections: [(id: ID, setChecks: [Bool])]) -> ID? {
        sections.first(where: { $0.setChecks.contains(false) })?.id ?? sections.first?.id
    }
}
