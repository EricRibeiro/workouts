import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct SetTableLayoutTests {
    @Test func supersetsRenumberByFirstAppearance() {
        #expect(SetTableLayout.supersetNumbers(for: [nil, 7, 7, nil, 3, 3]) == [nil, 1, 1, nil, 2, 2])
        #expect(SetTableLayout.supersetNumbers(for: [5, 2, 5, 2]) == [1, 2, 1, 2])
        #expect(SetTableLayout.supersetNumbers(for: []) == [])
    }

    @Test func aGroupOfOneIsNoSuperset() {
        #expect(SetTableLayout.supersetNumbers(for: [0, nil, 4, 4]) == [nil, nil, 1, 1])
    }

    @Test(arguments: [(120, "Rest 2:00"), (30, "Rest 0:30"), (90, "Rest 1:30"), (3600, "Rest 60:00")])
    func restCaption(seconds: Int, expected: String) {
        #expect(SetTableLayout.restCaption(seconds: seconds, defaultSeconds: 45) == expected)
    }

    @Test func restCaptionSaysOffForZero() {
        #expect(SetTableLayout.restCaption(seconds: 0, defaultSeconds: 90) == "Rest off")
    }

    @Test func restCaptionForNilFollowsTheDefault() {
        #expect(SetTableLayout.restCaption(seconds: nil, defaultSeconds: 90) == "Rest 1:30 (default)")
        #expect(SetTableLayout.restCaption(seconds: nil, defaultSeconds: 120) == "Rest 2:00 (default)")
        #expect(SetTableLayout.restCaption(seconds: nil, defaultSeconds: 0) == "Rest off")
    }

    @Test func reorderedMovesBeforeDestination() {
        #expect(SetTableLayout.reordered([1, 2, 3, 4], moving: [4], before: 2) == [1, 4, 2, 3])
        #expect(SetTableLayout.reordered([1, 2, 3, 4], moving: [1], before: 4) == [2, 3, 1, 4])
        #expect(SetTableLayout.reordered([1, 2, 3, 4], moving: [3, 1], before: 4) == [2, 1, 3, 4])
    }

    @Test func reorderedAppendsAtTheEnd() {
        #expect(SetTableLayout.reordered([1, 2, 3], moving: [1], before: nil) == [2, 3, 1])
        #expect(SetTableLayout.reordered([1, 2, 3], moving: [1], before: 1) == [2, 3, 1])
    }

    @Test func reorderedIgnoresUnknownIDs() {
        #expect(SetTableLayout.reordered([1, 2, 3], moving: [9], before: 2) == [1, 2, 3])
    }

    @Test func defaultFocusedSectionIsTheFirstWithAnUncheckedSet() {
        let sections = [
            (id: "a", setChecks: [true, true]), (id: "b", setChecks: [true, false]), (id: "c", setChecks: [false]),
        ]
        #expect(SetTableLayout.defaultFocusedSection(sections: sections) == "b")
    }

    @Test func defaultFocusedSectionFallsBackToTheFirstBlock() {
        #expect(
            SetTableLayout.defaultFocusedSection(sections: [(id: 1, setChecks: [true]), (id: 2, setChecks: [])]) == 1
        )
        #expect(SetTableLayout.defaultFocusedSection(sections: [(id: 1, setChecks: [])]) == 1)
        let none: [(id: Int, setChecks: [Bool])] = []
        #expect(SetTableLayout.defaultFocusedSection(sections: none) == nil)
    }
}
