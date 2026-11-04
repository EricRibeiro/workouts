import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct LibraryFilterTests {
    private let labels = LibraryLabels(
        bodyParts: ["legs": "Legs", "biceps": "Biceps", "back": "Back"],
        equipment: ["barbell": "Barbell", "dumbbell": "Dumbbells"]
    )

    private func info(_ name: String, bodyPart: String, equipment: [String]) -> ExerciseInfo {
        ExerciseInfo(
            id: UUID(),
            name: name,
            bodyPart: bodyPart,
            equipment: equipment,
            weightType: .barbell,
            isCustom: false
        )
    }

    private var sample: [ExerciseInfo] {
        [
            info("Back Squat", bodyPart: "legs", equipment: ["barbell"]),
            info("Goblet Squat", bodyPart: "legs", equipment: ["dumbbell", "kettlebell"]),
            info("Zottman Curl", bodyPart: "biceps", equipment: ["dumbbell"]),
        ]
    }

    @Test func noFiltersKeepsEverythingInOrder() {
        #expect(ExerciseFilter.apply(sample).map(\.name) == ["Back Squat", "Goblet Squat", "Zottman Curl"])
    }

    @Test func bodyPartFilter() {
        #expect(ExerciseFilter.apply(sample, bodyPart: "legs").map(\.name) == ["Back Squat", "Goblet Squat"])
        #expect(ExerciseFilter.apply(sample, bodyPart: "chest").isEmpty)
    }

    @Test func categoryMatchesAnyEquipmentKey() {
        #expect(ExerciseFilter.apply(sample, category: "kettlebell").map(\.name) == ["Goblet Squat"])
        #expect(ExerciseFilter.apply(sample, category: "dumbbell").map(\.name) == ["Goblet Squat", "Zottman Curl"])
    }

    @Test func bothFiltersCombine() {
        let result = ExerciseFilter.apply(sample, bodyPart: "legs", category: "dumbbell")
        #expect(result.map(\.name) == ["Goblet Squat"])
    }

    @Test func resultsCombineQueryAndFilters() throws {
        let store = ExerciseStore(catalog: try LibraryFixture.catalog())
        let everything = ExerciseFilter.results(in: store, query: "").map(\.name)
        #expect(everything.contains("Zottman Curl"))
        #expect(!everything.contains("Old Machine Press"))
        #expect(ExerciseFilter.results(in: store, query: "sentadilla").map(\.name) == ["Back Squat"])
        #expect(ExerciseFilter.results(in: store, query: "squat", bodyPart: "biceps").isEmpty)
        #expect(ExerciseFilter.results(in: store, query: "curl", bodyPart: "biceps").map(\.name) == ["Zottman Curl"])
    }

    @Test func resultsIncludeRetiredOnRequest() throws {
        let store = ExerciseStore(catalog: try LibraryFixture.catalog())
        let hidden = ExerciseFilter.results(in: store, query: "")
        let shown = ExerciseFilter.results(in: store, query: "", includeRetired: true)
        #expect(!hidden.contains { $0.isRetired })
        #expect(shown.contains { $0.name == "Old Machine Press" && $0.isRetired })
        #expect(shown.count == hidden.count + shown.filter(\.isRetired).count)
    }

    @Test func optionListsAreSortedByLabelAndSkipEmpty() {
        let list = sample + [info("Mystery", bodyPart: "", equipment: [])]
        #expect(ExerciseFilter.bodyParts(in: list, labels: labels) == ["biceps", "legs"])
        #expect(ExerciseFilter.categories(in: list, labels: labels) == ["barbell", "dumbbell", "kettlebell"])
    }

    @Test func labelsFallBackToHumanisedKeys() {
        #expect(ExerciseFilter.bodyPartLabel("legs", labels: labels) == "Legs")
        #expect(ExerciseFilter.bodyPartLabel("other", labels: labels) == "Other")
        #expect(ExerciseFilter.equipmentLabel("pull_up_bar", labels: labels) == "Pull up bar")
    }

    @Test func subtitleJoinsBodyPartAndEquipment() {
        #expect(ExerciseFilter.subtitle(for: sample[1], labels: labels) == "Legs · Dumbbells, Kettlebell")
        #expect(
            ExerciseFilter.subtitle(for: info("X", bodyPart: "", equipment: ["barbell"]), labels: labels) == "Barbell"
        )
        #expect(ExerciseFilter.subtitle(for: info("Y", bodyPart: "back", equipment: []), labels: labels) == "Back")
        #expect(ExerciseFilter.subtitle(for: info("Z", bodyPart: "", equipment: []), labels: labels).isEmpty)
    }
}
