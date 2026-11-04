import Testing

@testable import WorkoutsKit

@Suite struct SupersetGroupingTests {
    private typealias Item = (id: String, group: Int?)

    private func ids(_ items: [Item]) -> [String] { items.map(\.id) }
    private func groups(_ items: [Item]) -> [Int?] { items.map(\.group) }

    @Test func groupsTwoSeparateExercisesAtTheFirstMembersPosition() {
        let items: [Item] = [("a", nil), ("b", nil), ("c", nil), ("d", nil)]
        let result = SupersetGrouping.grouping(items, members: ["d", "b"])
        #expect(ids(result) == ["a", "b", "d", "c"])
        #expect(groups(result) == [nil, 1, 1, nil])
    }

    @Test func keepsTheListOrderOfTheMembersNotTheArgumentOrder() {
        let items: [Item] = [("a", nil), ("b", nil), ("c", nil)]
        let result = SupersetGrouping.grouping(items, members: ["c", "a"])
        #expect(ids(result) == ["a", "c", "b"])
        #expect(groups(result) == [1, 1, nil])
    }

    @Test func newGroupIsRenumberedByFirstAppearance() {
        let items: [Item] = [("a", nil), ("b", nil), ("c", 1), ("d", 1)]
        let result = SupersetGrouping.grouping(items, members: ["a", "b"])
        #expect(ids(result) == ["a", "b", "c", "d"])
        #expect(groups(result) == [1, 1, 2, 2])
    }

    @Test func existingGroupsRenumberTo123() {
        let items: [Item] = [("a", 7), ("b", 7), ("c", nil), ("d", 4), ("e", 4), ("f", nil), ("g", nil)]
        let result = SupersetGrouping.grouping(items, members: ["f", "g"])
        #expect(ids(result) == ["a", "b", "c", "d", "e", "f", "g"])
        #expect(groups(result) == [1, 1, nil, 2, 2, 3, 3])
    }

    @Test func movingAMemberOutDissolvesTheGroupItLeftAlone() {
        // c leaves {a, b, c} for a new pair with d: {a, b} survives.
        let items: [Item] = [("a", 1), ("b", 1), ("c", 1), ("d", nil)]
        let moved = SupersetGrouping.grouping(items, members: ["c", "d"])
        #expect(ids(moved) == ["a", "b", "c", "d"])
        #expect(groups(moved) == [1, 1, 2, 2])
        // Editing {a, b, c} down to {a, b}: c is left alone in the old group and dissolves.
        let edited = SupersetGrouping.grouping(items, members: ["a", "b"])
        #expect(groups(edited) == [1, 1, nil, nil])
    }

    @Test func takingOneOfAPairLeavesTheOtherUngrouped() {
        let items: [Item] = [("a", 1), ("b", 1), ("c", nil)]
        let result = SupersetGrouping.grouping(items, members: ["b", "c"])
        #expect(ids(result) == ["a", "b", "c"])
        #expect(groups(result) == [nil, 1, 1])
    }

    @Test func gatheringPullsMembersOverNonMembers() {
        let items: [Item] = [("a", nil), ("b", 1), ("c", nil), ("d", 1), ("e", nil)]
        let result = SupersetGrouping.grouping(items, members: ["a", "e", "d"])
        #expect(ids(result) == ["a", "d", "e", "b", "c"])
        #expect(groups(result) == [1, 1, 1, nil, nil])
    }

    @Test func fewerThanTwoPresentMembersGroupNothing() {
        let items: [Item] = [("a", nil), ("b", 5), ("c", 5)]
        let one = SupersetGrouping.grouping(items, members: ["a"])
        #expect(ids(one) == ["a", "b", "c"])
        #expect(groups(one) == [nil, 1, 1])
        let unknown = SupersetGrouping.grouping(items, members: ["a", "zzz"])
        #expect(groups(unknown) == [nil, 1, 1])
        #expect(groups(SupersetGrouping.grouping(items, members: [])) == [nil, 1, 1])
    }

    @Test func duplicateMembersCountOnce() {
        let items: [Item] = [("a", nil), ("b", nil)]
        let result = SupersetGrouping.grouping(items, members: ["a", "a"])
        #expect(groups(result) == [nil, nil])
    }

    @Test func removingOneOfAPairDissolvesTheOther() {
        let items: [Item] = [("a", 1), ("b", 1), ("c", 2), ("d", 2), ("e", 2)]
        let result = SupersetGrouping.removing("a", from: items)
        #expect(ids(result) == ["b", "c", "d", "e"])
        #expect(groups(result) == [nil, 1, 1, 1])
    }

    @Test func removingFromABiggerGroupKeepsIt() {
        let items: [Item] = [("a", 3), ("b", 3), ("c", 3), ("d", nil)]
        let result = SupersetGrouping.removing("b", from: items)
        #expect(ids(result) == ["a", "c", "d"])
        #expect(groups(result) == [1, 1, nil])
        #expect(groups(SupersetGrouping.removing("zzz", from: items)) == [1, 1, 1, nil])
    }
}
