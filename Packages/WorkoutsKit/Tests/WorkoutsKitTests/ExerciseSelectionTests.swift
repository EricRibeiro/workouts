import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct LibrarySelectionTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    private func info(_ id: UUID, _ name: String) -> ExerciseInfo {
        ExerciseInfo(id: id, name: name, weightType: .barbell, isCustom: false)
    }

    @Test func startsEmptyWithNothingEnabled() {
        let selection = ExerciseSelection()
        #expect(selection.count == 0)
        #expect(!selection.canAdd)
        #expect(!selection.canSuperset)
    }

    @Test func toggleKeepsTickOrder() {
        var selection = ExerciseSelection()
        let ticked = [selection.toggle(b), selection.toggle(a), selection.toggle(c)]
        #expect(ticked == [true, true, true])
        #expect(selection.ids == [b, a, c])
        let unticked = selection.toggle(a)
        #expect(!unticked)
        #expect(selection.ids == [b, c])
        let reticked = selection.toggle(a)
        #expect(reticked)
        #expect(selection.ids == [b, c, a])
    }

    @Test func supersetNeedsTwo() {
        var selection = ExerciseSelection()
        selection.toggle(a)
        #expect(selection.canAdd)
        #expect(!selection.canSuperset)
        selection.toggle(b)
        #expect(selection.canSuperset)
        #expect(selection.count == 2)
        selection.toggle(b)
        #expect(!selection.canSuperset)
    }

    @Test func selectIsIdempotent() {
        var selection = ExerciseSelection()
        selection.select(a)
        selection.select(b)
        selection.select(a)
        #expect(selection.ids == [a, b])
    }

    @Test func initDropsDuplicates() {
        #expect(ExerciseSelection(ids: [a, b, a]).ids == [a, b])
    }

    @Test func clearEmpties() {
        var selection = ExerciseSelection(ids: [a, b])
        selection.clear()
        #expect(selection.count == 0)
        #expect(!selection.contains(a))
    }

    @Test func resolveFollowsTickOrderAndSkipsUnknown() {
        let known = [a: info(a, "A"), c: info(c, "C")]
        let selection = ExerciseSelection(ids: [c, b, a])
        #expect(selection.resolve { known[$0] }.map(\.name) == ["C", "A"])
    }
}
