import Foundation
import Testing

@testable import WorkoutsKit

/// Small inline library with the real `library.json` shape (see `scripts/build-library`).
enum LibraryFixture {
    static let squat = UUID(uuidString: "00000000-0000-5000-8000-000000000001")!
    static let curl = UUID(uuidString: "00000000-0000-5000-8000-000000000002")!
    static let etirement = UUID(uuidString: "00000000-0000-5000-8000-000000000003")!
    static let retired = UUID(uuidString: "00000000-0000-5000-8000-000000000004")!

    static let json = """
        {
          "version": 1,
          "source": "smartworkout",
          "scrapedAt": "2026-11-03T01:00:02Z",
          "labels": {
            "bodyParts": {"legs": "Legs", "biceps": "Biceps"},
            "muscles": {"quadriceps": "Quadriceps"},
            "muscleGroups": {"legs": "Legs"},
            "equipment": {"barbell": "Barbell"}
          },
          "exercises": [
            \(exercise(id: squat, name: "Back Squat", bodyPart: "legs", weightType: "barbell",
                       aliases: ["Barbell Squat", "Sentadilla"], retired: false)),
            \(exercise(id: curl, name: "Zottman Curl", bodyPart: "biceps", weightType: "dumbbell",
                       aliases: nil, retired: false)),
            \(exercise(id: etirement, name: "Étirement", bodyPart: "legs", weightType: "unweighted",
                       aliases: ["Stretch"], retired: false)),
            \(exercise(id: retired, name: "Old Machine Press", bodyPart: "chest", weightType: "machine",
                       aliases: nil, retired: true))
          ]
        }
        """

    static func exercise(
        id: UUID,
        name: String,
        bodyPart: String,
        weightType: String,
        aliases: [String]?,
        retired: Bool,
        tags: [String] = ["strength"]
    ) -> String {
        let aliasField =
            aliases.map { list in
                "\"aliases\": [\(list.map { "\"\($0)\"" }.joined(separator: ","))],"
            } ?? ""
        return """
            {
              \(aliasField)
              "alternates": {"en": "https://example.com/\(name)"},
              "alternatives": ["\(squat.uuidString)"],
              "bodyPart": "\(bodyPart)",
              "description": "About \(name).",
              "equipment": ["barbell"],
              "hasThumbnails": true,
              "hasVideos": false,
              "id": "\(id.uuidString)",
              "instructions": ["Step one"],
              "laterality": "bilateral",
              "mechanics": "compound",
              "muscles": {"quadriceps": 80},
              "name": "\(name)",
              "recommended": [],
              "retired": \(retired),
              "source": "smartworkout",
              "sourceCreatedAt": "2026-10-08T20:31:00Z",
              "sourceId": "src-\(name.count)",
              "sourceUrl": "https://example.com",
              "tags": [\(tags.map { "\"\($0)\"" }.joined(separator: ","))],
              "tips": [],
              "mistakes": [],
              "usedCount": 3,
              "weightType": "\(weightType)"
            }
            """
    }

    static func catalog() throws -> LibraryCatalog {
        try LibraryCatalog(data: Data(json.utf8))
    }
}

@Suite struct LibraryCatalogTests {
    @Test func decodesTopLevelFields() throws {
        let catalog = try LibraryFixture.catalog()
        #expect(catalog.version == 1)
        #expect(catalog.source == "smartworkout")
        #expect(catalog.scrapedAt == "2026-11-03T01:00:02Z")
        #expect(catalog.labels.bodyParts["legs"] == "Legs")
        #expect(catalog.labels.muscles["quadriceps"] == "Quadriceps")
        #expect(catalog.labels.muscleGroups["legs"] == "Legs")
        #expect(catalog.labels.equipment["barbell"] == "Barbell")
        #expect(catalog.exercises.count == 4)
    }

    @Test func decodesExerciseFields() throws {
        let squat = try #require(try LibraryFixture.catalog().exercise(id: LibraryFixture.squat))
        #expect(squat.id == LibraryFixture.squat)
        #expect(squat.name == "Back Squat")
        #expect(squat.aliases == ["Barbell Squat", "Sentadilla"])
        #expect(squat.bodyPart == "legs")
        #expect(squat.weightType == .barbell)
        #expect(squat.mechanics == "compound")
        #expect(squat.laterality == "bilateral")
        #expect(squat.muscles == ["quadriceps": 80])
        #expect(squat.instructions == ["Step one"])
        #expect(squat.alternatives == [LibraryFixture.squat])
        #expect(squat.recommended.isEmpty)
        #expect(squat.usedCount == 3)
        #expect(squat.sourceCreatedAt == "2026-10-08T20:31:00Z")
        #expect(squat.alternates["en"] != nil)
        #expect(squat.hasThumbnails)
        #expect(!squat.hasVideos)
        #expect(!squat.retired)
    }

    @Test func missingAliasesDecodeAsEmpty() throws {
        let curl = try #require(try LibraryFixture.catalog().exercise(id: LibraryFixture.curl))
        #expect(curl.aliases.isEmpty)
    }

    @Test func lookupByIDAndMiss() throws {
        let catalog = try LibraryFixture.catalog()
        #expect(catalog.exercise(id: LibraryFixture.retired)?.retired == true)
        #expect(catalog.exercise(id: UUID()) == nil)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: (any Error).self) { try LibraryCatalog(data: Data("{}".utf8)) }
    }

    @Test func bundledThrowsWhenResourceIsMissing() {
        #expect(throws: LibraryCatalogError.missingResource) {
            try LibraryCatalog.bundled(in: Bundle(for: BundleToken.self))
        }
    }

    @Test func bundledReadsLibraryFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LibraryCatalogTests-\(UUID().uuidString)"
        )
        let library = root.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(LibraryFixture.json.utf8).write(to: library.appendingPathComponent("library.json"))
        let bundle = try #require(Bundle(url: root))
        let catalog = try LibraryCatalog.bundled(in: bundle)
        #expect(catalog.exercises.count == 4)
    }

    /// The shipped file: 1,038 exercises with unique ids, every cross-reference resolvable.
    @Test func decodesRealLibraryFile() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("Resources/Library/library.json")
        let catalog = try LibraryCatalog(data: Data(contentsOf: url))
        #expect(catalog.exercises.count == 1038)
        #expect(Set(catalog.exercises.map(\.id)).count == 1038)
        #expect(catalog.exercises.allSatisfy { catalog.exercise(id: $0.id)?.id == $0.id })
        #expect(
            catalog.exercises.allSatisfy { exercise in
                (exercise.alternatives + exercise.recommended).allSatisfy { catalog.exercise(id: $0) != nil }
            }
        )
        #expect(!catalog.labels.bodyParts.isEmpty)
    }
}

private final class BundleToken {}
