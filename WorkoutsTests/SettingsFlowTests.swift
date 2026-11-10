import Foundation
import SwiftData
import Testing
import WorkoutsKit

@testable import Workouts

@MainActor
struct SettingsFlowTests {
    private struct RefreshFailure: Error {}

    private struct RemovalFailure: LocalizedError {
        var errorDescription: String? { "The store is unavailable." }
    }

    /// An export file holding one custom exercise, written from a throwaway in-memory store.
    private func exportFile() async throws -> URL {
        let source = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        source.mainContext.insert(Exercise(name: "Zercher Squat"))
        try source.mainContext.save()
        return try await DataTransfer.writeExport(container: source, catalog: nil)
    }

    /// An export holding one custom exercise and one unfinished workout, written from a throwaway in-memory store.
    private func exportWithRunningWorkout() async throws -> (file: URL, exerciseID: UUID, workoutID: UUID) {
        let source = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        let exercise = Exercise(name: "Zercher Squat")
        let workout = Workout(name: "Bench Day", startedAt: Date().addingTimeInterval(-600))
        source.mainContext.insert(exercise)
        source.mainContext.insert(workout)
        try source.mainContext.save()
        let file = try await DataTransfer.writeExport(container: source, catalog: nil)
        return (file, exercise.id, workout.id)
    }

    private func engine(
        in container: ModelContainer,
        store: ExerciseStore
    ) throws -> ActiveWorkoutEngine {
        try ActiveWorkoutEngine(
            context: container.mainContext,
            store: store,
            settings: SettingsStore(backend: InMemoryBackend())
        )
    }

    @Test func runImportRaisesIsImportingThenReportsTheOutcome() async throws {
        let file = try await exportFile()
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        defer { withExtendedLifetime(container) {} }
        let flow = SettingsFlow()
        let task = flow.runImport(
            file,
            context: container.mainContext,
            catalog: nil,
            exerciseStore: nil,
            engine: nil,
            generation: nil
        )
        #expect(flow.isImporting)
        await task.value
        #expect(!flow.isImporting)
        #expect(flow.outcome?.title == "Import Complete")
        #expect(flow.outcome?.message.contains("Custom exercises: 1 added") == true)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Exercise>()) == 1)
    }

    @Test func refreshAfterImportShowsTheImportedExerciseAndResumesTheImportedWorkout() async throws {
        let (file, exerciseID, workoutID) = try await exportWithRunningWorkout()
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let store = ExerciseStore(catalog: try LibraryCatalog.bundled(in: .main))
        let engine = try engine(in: container, store: store)
        #expect(engine.workout == nil)
        #expect(store.exercise(id: exerciseID) == nil)
        let flow = SettingsFlow()
        await flow.performImport(file, context: context, catalog: nil, generation: nil) {
            try SettingsFlow.refreshAfterImport(context: context, exerciseStore: store, engine: engine)
        }
        #expect(flow.outcome?.title == "Import Complete")
        #expect(!(flow.outcome?.message.contains("could not refresh everything") ?? false))
        #expect(store.exercise(id: exerciseID)?.name == "Zercher Squat")
        #expect(engine.workout?.id == workoutID)
    }

    @Test func refreshAfterImportLeavesARunningWorkoutUntouched() async throws {
        let (file, exerciseID, _) = try await exportWithRunningWorkout()
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let store = ExerciseStore(catalog: try LibraryCatalog.bundled(in: .main))
        let engine = try engine(in: container, store: store)
        let running = try engine.startEmpty()
        let flow = SettingsFlow()
        await flow.performImport(file, context: context, catalog: nil, generation: nil) {
            try SettingsFlow.refreshAfterImport(context: context, exerciseStore: store, engine: engine)
        }
        #expect(store.exercise(id: exerciseID)?.name == "Zercher Squat")
        #expect(engine.workout === running)
        #expect(try context.fetchCount(FetchDescriptor<Workout>(predicate: Workout.inProgressPredicate)) == 1)
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

    @Test func aFailedFitnessRemovalIsReported() async {
        let flow = SettingsFlow()
        await flow.performTurnOff { throw RemovalFailure() }
        #expect(flow.outcome?.title == "Could Not Remove Fitness Data")
        #expect(flow.outcome?.message == "The store is unavailable.")
    }

    @Test func aSuccessfulFitnessRemovalReportsNothing() async {
        let flow = SettingsFlow()
        await flow.performTurnOff {}
        #expect(flow.outcome == nil)
    }
}
