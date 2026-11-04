import Testing

@testable import WorkoutsKit

@Suite struct LibraryMusclesTests {
    private let labels = LibraryLabels(muscles: ["chest": "Chest", "triceps": "Triceps", "empty": ""])

    @Test func thresholdBoundaryIsSeventy() {
        let split = LibraryMuscles.split(["chest": 70, "triceps": 69], labels: labels)
        #expect(split.primary == ["Chest"])
        #expect(split.secondary == ["Triceps"])
    }

    @Test func zeroIsDroppedAndOrderIsStrongestFirst() {
        let split = LibraryMuscles.split(
            ["chest": 100, "triceps": 40, "delts_front": 55, "lats": 0, "abs": 100],
            labels: labels
        )
        #expect(split.primary == ["Abs", "Chest"])
        #expect(split.secondary == ["Delts front", "Triceps"])
    }

    @Test func missingLabelIsMadeFromTheKey() {
        #expect(LibraryMuscles.label("chest_upper", labels: labels) == "Chest upper")
        #expect(LibraryMuscles.label("rear-delts", labels: labels) == "Rear delts")
        #expect(LibraryMuscles.label("empty", labels: labels) == "Empty")
        #expect(LibraryMuscles.label("chest", labels: labels) == "Chest")
        #expect(LibraryMuscles.label("", labels: labels) == "")
    }

    @Test func emptyInputGivesNothing() {
        let split = LibraryMuscles.split([:], labels: labels)
        #expect(split.primary.isEmpty)
        #expect(split.secondary.isEmpty)
    }
}
