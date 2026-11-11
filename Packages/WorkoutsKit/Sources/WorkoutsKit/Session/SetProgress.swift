import Foundation

/// How far through an exercise block the active workout is, over the rows that show a check.
public nonisolated struct SetProgress: Equatable, Sendable {
    private let checked: [Bool]

    /// `checked` has one entry per row that shows a check, in display order.
    public init(checked: [Bool]) {
        self.checked = checked
    }

    /// The index of the first set still to do, nil when every set is checked (or there are none).
    public var nextIndex: Int? {
        checked.firstIndex(of: false)
    }
}
