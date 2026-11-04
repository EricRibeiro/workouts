import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

/// Where Eric's real web export lives (`scripts/export-web`, task 1.7). Personal data, gitignored, so the
/// suite below runs only on the machine that produced it.
private nonisolated enum WebExportFixture {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static let url = repoRoot.appendingPathComponent("docs/port/fixtures/web-export.json")

    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}

@Suite(
    .enabled(
        if: WebExportFixture.exists,
        "docs/port/fixtures/web-export.json is missing: run scripts/export-web"
    )
)
struct ImportWebExportTests {
    private static func load() throws -> (doc: WorkoutsJSON, catalog: LibraryCatalog) {
        let doc = try WorkoutsJSON.decode(Data(contentsOf: WebExportFixture.url))
        let catalog = try LibraryCatalog(
            data: Data(
                contentsOf: WebExportFixture.repoRoot.appendingPathComponent("Resources/Library/library.json")
            )
        )
        return (doc, catalog)
    }

    @Test func importsWithoutUnknownOrDanglingReferencesThenChangesNothing() throws {
        let (doc, catalog) = try Self.load()
        #expect(doc.version == WorkoutsJSON.currentVersion)

        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        let context = container.mainContext

        let first = try Importer.apply(doc, to: context, catalog: catalog)
        #expect(first.unknownLibraryRefs.isEmpty, "unknown library refs: \(first.unknownLibraryRefs)")
        #expect(first.danglingReferences == 0)
        #expect(first[.folders].inserted == doc.folders.count)
        #expect(first[.templates].inserted == doc.templates.count)
        #expect(first[.customExercises].inserted == doc.customExercises.count)
        #expect(first[.stickyNotes].inserted == doc.stickyNotes.count)
        #expect(first[.workouts].inserted == doc.workouts.count)
        #expect(first[.workoutExercises].inserted == doc.workouts.reduce(0) { $0 + $1.exercises.count })
        #expect(
            first[.workoutSets].inserted
                == doc.workouts.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } }
        )

        let second = try Importer.apply(doc, to: context, catalog: catalog)
        #expect(!second.changedAnything, "a second import changed rows: \(second)")
        #expect(second.unknownLibraryRefs.isEmpty)
        #expect(second.danglingReferences == 0)
    }
}
