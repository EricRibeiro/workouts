import Foundation
import SwiftData
import Testing
import WorkoutsKit

@testable import Workouts

@MainActor
struct SettingsFlowTests {
    private struct RefreshFailure: Error {}

    /// An export file holding one custom exercise, written from a throwaway in-memory store.
    private func exportFile() async throws -> URL {
        let source = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        source.mainContext.insert(Exercise(name: "Zercher Squat"))
        try source.mainContext.save()
        return try await DataTransfer.writeExport(container: source, catalog: nil)
    }

    @Test func aSuccessfulImportReportsItsSummaryAndRaisesTheBackfill() async throws {
        let file = try await exportFile()
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let flow = SettingsFlow()
        await flow.performImport(file, context: context, catalog: nil, generation: nil, refresh: {})
        #expect(flow.outcome?.title == "Import Complete")
        #expect(flow.outcome?.message.contains("Custom exercises: 1 added") == true)
        #expect(flow.backfillRequest == 1)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
    }

    @Test func aFailingFollowUpIsNotReportedAsAFailedImport() async throws {
        let file = try await exportFile()
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let flow = SettingsFlow()
        await flow.performImport(
            file,
            context: context,
            catalog: nil,
            generation: nil,
            refresh: { throw RefreshFailure() }
        )
        #expect(flow.outcome?.title == "Import Complete")
        #expect(flow.outcome?.message.contains("Custom exercises: 1 added") == true)
        #expect(flow.outcome?.message.contains("could not refresh everything") == true)
        // The Fitness look-up for the imported history still runs.
        #expect(flow.backfillRequest == 1)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
    }

    @Test func anUnreadableFileIsAFailedImportWithoutABackfill() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: file)
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let flow = SettingsFlow()
        await flow.performImport(file, context: context, catalog: nil, generation: nil, refresh: {})
        #expect(flow.outcome?.title == "Could Not Import")
        #expect(flow.backfillRequest == 0)
    }
}
