import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct LibraryExerciseStoreTests {
    private func store(custom: [Exercise] = []) throws -> ExerciseStore {
        ExerciseStore(catalog: try LibraryFixture.catalog(), custom: custom)
    }

    private func names(_ list: [ExerciseInfo]) -> [String] { list.map(\.name) }

    @Test func infoFromLibraryExercise() throws {
        let squat = try #require(try LibraryFixture.catalog().exercise(id: LibraryFixture.squat))
        let info = ExerciseInfo(squat)
        #expect(info.id == squat.id)
        #expect(info.name == "Back Squat")
        #expect(info.aliases == ["Barbell Squat", "Sentadilla"])
        #expect(info.weightType == .barbell)
        #expect(!info.isCustom)
        #expect(!info.isRetired)
        #expect(info.unit == nil && info.barType == nil && info.restSeconds == nil)
    }

    @Test func isometricLibraryExercisesAreTimedByDefault() throws {
        let plankID = UUID()
        let json = LibraryFixture.json.replacingOccurrences(
            of: "\"exercises\": [",
            with: "\"exercises\": [\n"
                + LibraryFixture.exercise(
                    id: plankID,
                    name: "Plank",
                    bodyPart: "abs",
                    weightType: "bodyweight",
                    aliases: nil,
                    retired: false,
                    tags: ["isometric"]
                ) + ","
        )
        let catalog = try LibraryCatalog(data: Data(json.utf8))
        let plank = ExerciseInfo(try #require(catalog.exercise(id: plankID)))
        let squat = ExerciseInfo(try #require(catalog.exercise(id: LibraryFixture.squat)))
        let custom = ExerciseInfo(Exercise(name: "Hold", weightType: .bodyweight))
        #expect(plank.isTimed)
        #expect(!squat.isTimed)
        #expect(!custom.isTimed)
    }

    @Test func infoFromCustomExercise() {
        let custom = Exercise(
            name: "Sled Push",
            aliases: ["Prowler"],
            equipment: ["sled"],
            bodyPart: "legs",
            weightType: .weighted,
            unit: .kg,
            barType: .none,
            barWeight: 20,
            restSeconds: 60,
            retired: true
        )
        let info = ExerciseInfo(custom)
        #expect(info.id == custom.id)
        #expect(info.isCustom && info.isRetired)
        #expect(info.aliases == ["Prowler"])
        #expect(info.equipment == ["sled"])
        #expect(info.bodyPart == "legs")
        #expect(info.weightType == .weighted)
        #expect(info.unit == .kg)
        #expect(info.barType == BarType.none)
        #expect(info.barWeight == 20)
        #expect(info.restSeconds == 60)
    }

    @Test func lookupIsCatalogUnionCustom() throws {
        let custom = Exercise(name: "Sled Push", weightType: .weighted)
        let store = try store(custom: [custom])
        #expect(store.exercise(id: LibraryFixture.squat)?.isCustom == false)
        #expect(store.exercise(id: custom.id)?.name == "Sled Push")
        #expect(store.exercise(id: custom.id)?.isCustom == true)
        #expect(store.exercise(id: UUID()) == nil)
        #expect(store.all(includeRetired: true).count == 5)
    }

    @Test func retiredRowsResolveByIDButAreHiddenByDefault() throws {
        let archived = Exercise(name: "Archived Move", retired: true)
        let store = try store(custom: [archived])
        #expect(store.exercise(id: LibraryFixture.retired)?.isRetired == true)
        #expect(store.exercise(id: archived.id)?.isRetired == true)
        #expect(!names(store.all()).contains("Old Machine Press"))
        #expect(!names(store.all()).contains("Archived Move"))
        #expect(names(store.all(includeRetired: true)).contains("Old Machine Press"))
        #expect(names(store.all(includeRetired: true)).contains("Archived Move"))
    }

    @Test func allSortsByNameIgnoringCaseAndAccents() throws {
        let store = try store(custom: [
            Exercise(name: "arnold press"), Exercise(name: "Zebra Walk"), Exercise(name: "Élan Row"),
        ])
        // Étirement sorts with E, not after Z; lowercase "arnold" sorts with A.
        #expect(
            names(store.all()) == [
                "arnold press", "Back Squat", "Élan Row", "Étirement", "Zebra Walk", "Zottman Curl",
            ]
        )
    }

    @Test func equalNamesTieBreakOnID() throws {
        let low = Exercise(id: UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!, name: "Twin")
        let high = Exercise(id: UUID(uuidString: "00000000-0000-4000-8000-0000000000BB")!, name: "twin")
        let store = try store(custom: [high, low])
        #expect(store.all().filter { $0.name.lowercased() == "twin" }.map(\.id) == [low.id, high.id])
    }

    @Test func emptyAndBlankQueryReturnAll() throws {
        let store = try store()
        #expect(store.search("") == store.all())
        #expect(store.search("   \n ") == store.all())
        #expect(store.search("", includeRetired: true).count == 4)
    }

    @Test func searchMatchesNameSubstringCaseInsensitively() throws {
        #expect(names(try store().search("ZOTT")) == ["Zottman Curl"])
    }

    @Test func searchMatchesAliases() throws {
        #expect(names(try store().search("barbell squat")) == ["Back Squat"])
        #expect(names(try store().search("stretch")) == ["Étirement"])
    }

    @Test func searchIsAccentInsensitiveBothWays() throws {
        let store = try store()
        #expect(names(store.search("etirement")) == ["Étirement"])
        #expect(names(store.search("ÉTIREMENT")) == ["Étirement"])
        #expect(names(store.search("sentadílla")) == ["Back Squat"])
    }

    @Test func searchRequiresEveryWordAcrossNameAndAliases() throws {
        let store = try store()
        // "back" is in the name, "sentadilla" only in an alias.
        #expect(names(store.search("sentadilla back")) == ["Back Squat"])
        #expect(names(store.search("  back   squat ")) == ["Back Squat"])
        #expect(store.search("back curl").isEmpty)
        #expect(store.search("squat zzz").isEmpty)
    }

    @Test func searchExcludesRetiredUnlessAsked() throws {
        let store = try store()
        #expect(store.search("machine").isEmpty)
        #expect(names(store.search("machine", includeRetired: true)) == ["Old Machine Press"])
    }

    @Test func searchIncludesCustomExercisesAndTheirAliases() throws {
        let custom = Exercise(name: "Sled Push", aliases: ["Prowler"])
        #expect(names(try store(custom: [custom]).search("prowler")) == ["Sled Push"])
    }

    @Test func setCustomReplacesTheCustomRows() throws {
        let first = Exercise(name: "First")
        let second = Exercise(name: "Second")
        let store = try store(custom: [first])
        #expect(store.exercise(id: first.id) != nil)
        store.setCustom([second])
        #expect(store.exercise(id: first.id) == nil)
        #expect(store.exercise(id: second.id) != nil)
        #expect(store.exercise(id: LibraryFixture.squat) != nil)
    }

    @Test func canDeleteOnlyWhenUnreferenced() {
        let id = UUID()
        #expect(ExerciseStore.canDelete(customID: id, referencedIDs: []))
        #expect(ExerciseStore.canDelete(customID: id, referencedIDs: [UUID()]))
        #expect(!ExerciseStore.canDelete(customID: id, referencedIDs: [id, UUID()]))
    }

    @Test func removalDeletesArchivesOrRefuses() throws {
        let unused = Exercise(name: "Unused")
        let used = Exercise(name: "Used")
        let store = try store(custom: [unused, used])
        #expect(store.removal(of: unused.id, referencedIDs: [used.id]) == .delete)
        #expect(store.removal(of: used.id, referencedIDs: [used.id]) == .archive)
        #expect(store.removal(of: LibraryFixture.squat, referencedIDs: []) == .notAllowed)
        #expect(store.removal(of: UUID(), referencedIDs: []) == .notAllowed)
    }

    @Test func foldStripsCaseAndDiacritics() {
        #expect(ExerciseStore.fold("Élan Ñandú") == "elan nandu")
    }

    @Test func realLibraryResolvesAndSearches() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try LibraryCatalog(
            data: Data(contentsOf: repoRoot.appendingPathComponent("Resources/Library/library.json"))
        )
        let store = ExerciseStore(catalog: catalog)
        #expect(store.all().count == 1038)
        let hyper = store.search("reverse hyper")
        #expect(hyper.contains { $0.name == "45-Degree Reverse Hyperextension" })
    }
}
