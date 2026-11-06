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

    // MARK: reordered

    @Test func reorderingAMemberAwayFromItsPartnerLeavesTheGroup() {
        let items: [Item] = [("a", 1), ("b", 1), ("c", nil), ("d", nil)]
        // b dragged past c: the pair is split; b is the mover, a is freed, nothing is left grouped.
        let moved = SupersetGrouping.reordered(items, to: ["a", "c", "b", "d"])
        #expect(ids(moved) == ["a", "c", "b", "d"])
        #expect(groups(moved) == [nil, nil, nil, nil])
        // The other way round: a dragged to the end.
        #expect(groups(SupersetGrouping.reordered(items, to: ["b", "c", "d", "a"])) == [nil, nil, nil, nil])
    }

    @Test func reorderingOneMemberOfATripleKeepsTheOtherTwo() {
        let items: [Item] = [("a", 1), ("b", 1), ("c", 1), ("d", nil)]
        let moved = SupersetGrouping.reordered(items, to: ["a", "b", "d", "c"])
        #expect(ids(moved) == ["a", "b", "d", "c"])
        #expect(groups(moved) == [1, 1, nil, nil])
        // Moving the first member out takes it, not the remaining pair.
        #expect(groups(SupersetGrouping.reordered(items, to: ["b", "c", "d", "a"])) == [1, 1, nil, nil])
    }

    @Test func reorderingThatKeepsGroupsContiguousChangesNothingButOrder() {
        let items: [Item] = [("a", nil), ("b", 1), ("c", 1), ("d", 2), ("e", 2)]
        // The whole pair moves (and a member swaps within its pair): still contiguous.
        let moved = SupersetGrouping.reordered(items, to: ["d", "e", "a", "c", "b"])
        #expect(ids(moved) == ["d", "e", "a", "c", "b"])
        #expect(groups(moved) == [1, 1, nil, 2, 2])
    }

    @Test func aMoveCanSplitOneGroupWhileAnotherStays() {
        let items: [Item] = [("a", 1), ("b", 1), ("c", 2), ("d", 2)]
        let moved = SupersetGrouping.reordered(items, to: ["a", "c", "b", "d"])
        #expect(groups(moved) == [nil, nil, nil, nil])
        let intact = SupersetGrouping.reordered(items, to: ["c", "d", "a", "b"])
        #expect(groups(intact) == [1, 1, 2, 2])
    }

    // A non-member dropped between members keeps the superset whole: it lands after the run.

    @Test func aNonMemberDroppedInsideAPairLandsAfterIt() {
        let items: [Item] = [("a", 1), ("b", 1), ("c", nil)]
        // The adjacent swap alone is ambiguous (b down or c up); the drag says c moved.
        let moved = SupersetGrouping.reordered(items, to: ["a", "c", "b"], moving: ["c"])
        #expect(ids(moved) == ["a", "b", "c"])
        #expect(groups(moved) == [1, 1, nil])
        // The same order with b as the dragged row pulls b out, as before.
        let pulled = SupersetGrouping.reordered(items, to: ["a", "c", "b"], moving: ["b"])
        #expect(ids(pulled) == ["a", "c", "b"])
        #expect(groups(pulled) == [nil, nil, nil])
        // Without a hint the ambiguous order keeps the member reading.
        #expect(groups(SupersetGrouping.reordered(items, to: ["a", "c", "b"])) == [nil, nil, nil])
    }

    @Test func aNonMemberDroppedInsideATripleLandsAfterItWithoutEvictingAnyone() {
        let items: [Item] = [("a", 1), ("b", 1), ("d", 1), ("c", nil)]
        // Unambiguous: only c's removal reconciles the orders, so no hint is needed.
        let moved = SupersetGrouping.reordered(items, to: ["a", "c", "b", "d"])
        #expect(ids(moved) == ["a", "b", "d", "c"])
        #expect(groups(moved) == [1, 1, 1, nil])
        let hinted = SupersetGrouping.reordered(items, to: ["a", "c", "b", "d"], moving: ["c"])
        #expect(ids(hinted) == ["a", "b", "d", "c"])
        #expect(groups(hinted) == [1, 1, 1, nil])
    }

    @Test func aNonMemberDroppedInsideAGroupInTheMiddleOfAListKeepsTheOtherGroups() {
        let items: [Item] = [("x", nil), ("a", 1), ("b", 1), ("c", 2), ("d", 2), ("y", nil)]
        // y dragged between c and d: lands after d; both groups survive.
        let moved = SupersetGrouping.reordered(items, to: ["x", "a", "b", "c", "y", "d"], moving: ["y"])
        #expect(ids(moved) == ["x", "a", "b", "c", "d", "y"])
        #expect(groups(moved) == [nil, 1, 1, 2, 2, nil])
    }

    @Test func aWrongHintIsIgnored() {
        let items: [Item] = [("a", 1), ("b", 1), ("d", 1), ("c", nil)]
        let moved = SupersetGrouping.reordered(items, to: ["a", "c", "b", "d"], moving: ["a"])
        #expect(ids(moved) == ["a", "b", "d", "c"])
        #expect(groups(moved) == [1, 1, 1, nil])
    }

    @Test func aMultiRowMoveStillKeepsTheLongestRun() {
        let items: [Item] = [("a", 1), ("b", 1), ("c", 1), ("d", 1), ("x", nil), ("y", nil)]
        // Two rows moved: no single mover explains it, so only the longest run (earliest on a tie) stays.
        let moved = SupersetGrouping.reordered(items, to: ["x", "a", "b", "y", "c", "d"])
        #expect(ids(moved) == ["x", "a", "b", "y", "c", "d"])
        #expect(groups(moved) == [nil, 1, 1, nil, nil, nil])
    }
}
