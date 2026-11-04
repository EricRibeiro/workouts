import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

/// What Settings → Import… / Export… rely on (task 5.7b): the file name, the result text, and the app's own flow of
/// exporting from one context, importing through a separate (background) context, and importing again.
@Suite struct ImportExportFlowTests {
    private static func catalog() throws -> LibraryCatalog {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try LibraryCatalog(
            data: Data(contentsOf: repoRoot.appendingPathComponent("Resources/Library/library.json"))
        )
    }

    @Test func exportFileNameUsesTheDayInTheGivenTimeZone() throws {
        // 2026-11-04 01:30 UTC is still 2026-11-03 in Los Angeles.
        let date = Date(timeIntervalSince1970: 1_793_755_800)
        let utc = try #require(TimeZone(identifier: "UTC"))
        let la = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(WorkoutsJSON.exportFileName(for: date, timeZone: utc) == "workouts-export-2026-11-04.json")
        #expect(WorkoutsJSON.exportFileName(for: date, timeZone: la) == "workouts-export-2026-11-03.json")
    }

    @Test func summaryListsParentRowsAndNotesUnknownRefs() {
        var report = ImportReport()
        report[.workouts] = ImportCounts(inserted: 3, updated: 1, skipped: 46)
        report[.workoutSets] = ImportCounts(inserted: 900)
        report[.templates] = ImportCounts(skipped: 2)
        report.unknownLibraryRefs = [UnknownLibraryRef(source: "s", sourceId: "1", names: ["X"], uses: 4)]
        report.danglingReferences = 2

        #expect(report.headline == "Import Complete")
        #expect(
            report.summary == """
                Templates: 0 added, 0 updated, 2 skipped
                Workouts: 3 added, 1 updated, 46 skipped
                1 library exercise is not in this version of the app; their names were kept.
                2 links to a missing folder or template could not be restored.
                """
        )
    }

    @Test func aReImportReportsNothingNewAndAnEmptyFileSaysSo() {
        var again = ImportReport()
        again[.workouts] = ImportCounts(skipped: 5)
        #expect(again.headline == "Nothing New to Import")
        #expect(again.summary == "Workouts: 0 added, 0 updated, 5 skipped")
        #expect(ImportReport().summary == "The file had no data.")
    }

    @Test func anUnsupportedVersionHasAReadableMessage() {
        #expect(ImportError.unsupportedVersion(9).localizedDescription.contains("version 9"))
    }

    @Test func exportThenImportThroughASeparateContextIsIdempotent() throws {
        let catalog = try Self.catalog()
        let source = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        try SampleData.seed(into: source.mainContext, catalog: catalog, now: Date(timeIntervalSince1970: 0), seed: 1)
        let data = try Exporter.document(from: ModelContext(source), catalog: catalog).encoded()

        // The app imports on its own context and the main context sees the result.
        let target = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        let doc = try WorkoutsJSON.decode(data)
        let first = try Importer.apply(doc, to: ModelContext(target), catalog: catalog)
        #expect(first.changedAnything)
        #expect(first[.workouts].inserted == SampleData.finishedWorkoutCount)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<Workout>()) == SampleData.finishedWorkoutCount)

        let second = try Importer.apply(doc, to: ModelContext(target), catalog: catalog)
        #expect(second.changedAnything == false)
        #expect(second.headline == "Nothing New to Import")
        #expect(second[.workouts] == ImportCounts(skipped: SampleData.finishedWorkoutCount))
        #expect(try target.mainContext.fetchCount(FetchDescriptor<Workout>()) == SampleData.finishedWorkoutCount)
    }
}
