import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct ExerciseQueryTests {
    private static let catalogJSON = """
        {"version": 1, "labels": {
            "bodyParts": {"legs": "Legs", "biceps": "Biceps", "rear_delts": "Rear Delts", "core": "Core"},
            "equipment": {"barbell": "Barbell", "dumbbell": "Dumbbells", "cable": "Cable Machine"}
        }, "exercises": []}
        """

    private func custom(
        _ name: String,
        bodyPart: String,
        equipment: [String],
        aliases: [String] = [],
        retired: Bool = false
    ) -> Exercise {
        Exercise(
            name: name,
            aliases: aliases,
            equipment: equipment,
            bodyPart: bodyPart,
            weightType: .weighted,
            retired: retired
        )
    }

    private func store() throws -> ExerciseStore {
        let catalog = try LibraryCatalog(data: Data(Self.catalogJSON.utf8))
        return ExerciseStore(
            catalog: catalog,
            custom: [
                custom("Back Squat", bodyPart: "legs", equipment: ["barbell"], aliases: ["Sentadilla"]),
                custom("Goblet Squat", bodyPart: "legs", equipment: ["dumbbell", "kettlebell"]),
                custom("Zottman Curl", bodyPart: "biceps", equipment: ["dumbbell"]),
                custom("Reverse Fly", bodyPart: "rear_delts", equipment: ["dumbbell"]),
                custom("Face Pull", bodyPart: "rear_delts", equipment: ["cable"]),
                custom("Étirement", bodyPart: "legs", equipment: []),
                custom("Old Press", bodyPart: "legs", equipment: ["barbell"], retired: true),
            ]
        )
    }

    private func names(_ list: [ExerciseInfo]) -> [String] { list.map(\.name) }

    @Test func bodyPartAlone() throws {
        let result = try store().matches(ExerciseQuery(bodyParts: ["legs"]))
        #expect(names(result) == ["Back Squat", "Étirement", "Goblet Squat"])
    }

    @Test func bodyPartIsAnyOf() throws {
        let result = try store().matches(ExerciseQuery(bodyParts: ["biceps", "rear_delts"]))
        #expect(names(result) == ["Face Pull", "Reverse Fly", "Zottman Curl"])
    }

    @Test func categoryAlone() throws {
        let result = try store().matches(ExerciseQuery(categories: ["dumbbell"]))
        #expect(names(result) == ["Goblet Squat", "Reverse Fly", "Zottman Curl"])
    }

    @Test func categoryIsAnyOf() throws {
        let result = try store().matches(ExerciseQuery(categories: ["barbell", "cable"]))
        #expect(names(result) == ["Back Squat", "Face Pull"])
    }

    @Test func equipmentAlone() throws {
        let result = try store().matches(ExerciseQuery(equipment: ["kettlebell"]))
        #expect(names(result) == ["Goblet Squat"])
    }

    @Test func equipmentMatchesAnyOfTheExercisesEquipment() throws {
        // Goblet Squat has two equipment keys; either one is enough.
        let result = try store().matches(ExerciseQuery(equipment: ["dumbbell"]))
        #expect(names(result).contains("Goblet Squat"))
    }

    @Test func facetsCombineWithAnd() throws {
        let store = try store()
        let query = ExerciseQuery(bodyParts: ["rear_delts"], equipment: ["dumbbell"])
        #expect(names(store.matches(query)) == ["Reverse Fly"])
        let both = ExerciseQuery(bodyParts: ["legs"], categories: ["dumbbell"], equipment: ["kettlebell"])
        #expect(names(store.matches(both)) == ["Goblet Squat"])
        #expect(store.matches(ExerciseQuery(bodyParts: ["biceps"], equipment: ["cable"])).isEmpty)
    }

    @Test func wordsAloneUseAllWordsSearch() throws {
        let store = try store()
        let query = ExerciseQuery(words: ["squat"])
        #expect(names(store.matches(query)) == names(store.search("squat")))
        // Aliases count, and several words must all match (across name and alias).
        #expect(names(store.matches(ExerciseQuery(words: ["back", "sentadilla"]))) == ["Back Squat"])
        // A word may itself hold several words.
        #expect(names(store.matches(ExerciseQuery(words: ["goblet squat"]))) == ["Goblet Squat"])
    }

    @Test func wordsAndFacetsCombine() throws {
        let store = try store()
        let query = ExerciseQuery(bodyParts: ["legs"], equipment: ["dumbbell"], words: ["squat"])
        #expect(names(store.matches(query)) == ["Goblet Squat"])
        #expect(store.matches(ExerciseQuery(bodyParts: ["biceps"], words: ["squat"])).isEmpty)
    }

    @Test func labelsAndKeysBothWork() throws {
        let store = try store()
        let delts = ["Face Pull", "Reverse Fly"]
        #expect(names(store.matches(ExerciseQuery(bodyParts: ["Rear Delts"]))) == delts)
        #expect(names(store.matches(ExerciseQuery(bodyParts: ["rear_delts"]))) == delts)
        #expect(names(store.matches(ExerciseQuery(bodyParts: ["rear-delts"]))) == delts)
        let byKey = store.matches(ExerciseQuery(equipment: ["dumbbell"]))
        #expect(store.matches(ExerciseQuery(equipment: ["Dumbbells"])) == byKey)
        #expect(names(store.matches(ExerciseQuery(categories: ["Cable Machine"]))) == ["Face Pull"])
    }

    @Test func caseAndDiacriticsAreIgnored() throws {
        let store = try store()
        let legs = ["Back Squat", "Étirement", "Goblet Squat"]
        #expect(names(store.matches(ExerciseQuery(bodyParts: ["LEGS"]))) == legs)
        #expect(names(store.matches(ExerciseQuery(bodyParts: ["Léğs"]))) == legs)
        #expect(names(store.matches(ExerciseQuery(equipment: ["  DUMBBELLS "]))).contains("Zottman Curl"))
        #expect(names(store.matches(ExerciseQuery(words: ["ETIREMENT"]))) == ["Étirement"])
        #expect(names(store.matches(ExerciseQuery(words: ["étirement"]))) == ["Étirement"])
    }

    @Test func unknownValueMatchesNothing() throws {
        let store = try store()
        #expect(store.matches(ExerciseQuery(bodyParts: ["tentacles"])).isEmpty)
        #expect(store.matches(ExerciseQuery(categories: ["jetpack"])).isEmpty)
        #expect(store.matches(ExerciseQuery(equipment: ["jetpack"], words: ["squat"])).isEmpty)
        #expect(store.matches(ExerciseQuery(bodyParts: ["legs"], equipment: ["jetpack"])).isEmpty)
    }

    @Test func unknownAlongsideKnownStillMatchesTheKnown() throws {
        let result = try store().matches(ExerciseQuery(bodyParts: ["tentacles", "biceps"]))
        #expect(names(result) == ["Zottman Curl"])
    }

    @Test func blankValuesAreUnspecified() throws {
        let store = try store()
        let blank = ExerciseQuery(bodyParts: [""], categories: ["  "], equipment: [" "], words: ["", " "])
        #expect(blank.isEmpty)
        #expect(store.matches(blank) == store.all())
        let mixed = ExerciseQuery(bodyParts: ["", "biceps"])
        #expect(names(store.matches(mixed)) == ["Zottman Curl"])
    }

    @Test func emptyQueryIsPlainSearchWithNoWords() throws {
        let store = try store()
        let query = ExerciseQuery()
        #expect(query.isEmpty)
        #expect(store.matches(query) == store.search(""))
        #expect(store.matches(query) == store.all())
        #expect(store.matches(query, includeRetired: true) == store.all(includeRetired: true))
    }

    @Test func isEmptyIsFalseWithAnyFieldSet() {
        #expect(!ExerciseQuery(bodyParts: ["legs"]).isEmpty)
        #expect(!ExerciseQuery(categories: ["barbell"]).isEmpty)
        #expect(!ExerciseQuery(equipment: ["cable"]).isEmpty)
        #expect(!ExerciseQuery(words: ["squat"]).isEmpty)
    }

    @Test func retiredExcludedByDefault() throws {
        let store = try store()
        let query = ExerciseQuery(bodyParts: ["legs"], equipment: ["barbell"])
        #expect(names(store.matches(query)) == ["Back Squat"])
        #expect(names(store.matches(query, includeRetired: true)) == ["Back Squat", "Old Press"])
        #expect(!names(store.matches(ExerciseQuery(words: ["press"]))).contains("Old Press"))
    }

    @Test func resultsSortedByName() throws {
        let result = try store().matches(ExerciseQuery(equipment: ["dumbbell", "cable", "barbell"]))
        #expect(names(result) == ["Back Squat", "Face Pull", "Goblet Squat", "Reverse Fly", "Zottman Curl"])
    }

    @Test func codableRoundTripWithStableKeys() throws {
        let query = ExerciseQuery(
            bodyParts: ["legs"],
            categories: ["barbell"],
            equipment: ["dumbbell"],
            words: ["squat"]
        )
        let data = try JSONEncoder().encode(query)
        #expect(try JSONDecoder().decode(ExerciseQuery.self, from: data) == query)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["bodyParts", "categories", "equipment", "words"])
        #expect(object["bodyParts"] as? [String] == ["legs"])
        #expect(object["words"] as? [String] == ["squat"])
    }

    @Test func decodesFromHandWrittenJSON() throws {
        let json = #"{"bodyParts":["Rear Delts"],"categories":[],"equipment":["Dumbbells"],"words":[]}"#
        let query = try JSONDecoder().decode(ExerciseQuery.self, from: Data(json.utf8))
        #expect(query == ExerciseQuery(bodyParts: ["Rear Delts"], equipment: ["Dumbbells"]))
        #expect(names(try store().matches(query)) == ["Reverse Fly"])
    }
}
