import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

/// The background reader must give exactly what the synchronous main-actor functions give over the same store.
@Suite struct WorkoutStatsReaderTests {
    private static let now = Date(timeIntervalSince1970: 1_793_000_000)

    private static func realCatalog() throws -> LibraryCatalog {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try LibraryCatalog(
            data: Data(contentsOf: repoRoot.appendingPathComponent("Resources/Library/library.json"))
        )
    }

    /// A seeded in-memory store plus an unfinished workout, saved so a second context sees it.
    private func seededContainer(catalog: LibraryCatalog) throws -> ModelContainer {
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        let context = container.mainContext
        try SampleData.seed(into: context, catalog: catalog, now: Self.now, workoutCount: 40)
        let open = Workout(name: "In progress", startedAt: Self.now)
        let row = WorkoutExercise(exerciseID: catalog.exercises[0].id, unit: .kg, workout: open)
        _ = WorkoutSet(position: 0, weight: 500, reps: 5, completed: true, workoutExercise: row)
        context.insert(open)
        try context.save()
        return container
    }

    @Test(arguments: [WeightUnit.kg, .lb])
    func bestSetTextsEqualTheSynchronousWalk(unit: WeightUnit) async throws {
        let catalog = try Self.realCatalog()
        let store = ExerciseStore(catalog: catalog)
        let container = try seededContainer(catalog: catalog)
        let options = RecordsOptions(formula: .brzycki, displayUnit: unit)

        let finished = try container.mainContext.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.finishedAt != nil })
        )
        let expected = ExerciseBestSets.texts(
            from: ExerciseBestSets.sessions(from: finished) { store.exercise(id: $0)?.weightType },
            options: options
        )
        let actual = try await WorkoutStatsReader.loadBestSetTexts(
            in: container,
            weightTypes: store.weightTypes,
            options: options
        )

        #expect(!expected.isEmpty)
        #expect(actual == expected)
    }

    @Test(arguments: [WeightUnit.kg, .lb])
    func historySummaryEqualsTheSynchronousBuild(unit: WeightUnit) async throws {
        let catalog = try Self.realCatalog()
        let store = ExerciseStore(catalog: catalog)
        let container = try seededContainer(catalog: catalog)
        let options = RecordsOptions(formula: .epley, displayUnit: unit)

        let finished = try container.mainContext.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.finishedAt != nil })
        )
        let expected = HistoryDashboard.build(
            from: finished,
            weightType: { store.exercise(id: $0)?.weightType },
            options: options
        )
        let actual = try await WorkoutStatsReader.loadHistorySummary(
            in: container,
            weightTypes: store.weightTypes,
            options: options
        )

        #expect(expected.entries.count == 40)
        #expect(!expected.recentPRs.isEmpty)
        #expect(actual == expected)
    }

    @Test func aFreshReaderSeesWhatTheMainContextSaved() async throws {
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        let exerciseID = UUID()
        let none = try await WorkoutStatsReader(modelContainer: container)
            .historySummary(weightTypes: [:], options: RecordsOptions())
        #expect(none.entries.isEmpty)

        let workout = Workout(name: "Pull", startedAt: Self.now, finishedAt: Self.now.addingTimeInterval(3_600))
        let row = WorkoutExercise(exerciseID: exerciseID, unit: .kg, workout: workout)
        _ = WorkoutSet(position: 0, weight: 100, reps: 5, completed: true, workoutExercise: row)
        container.mainContext.insert(workout)
        try container.mainContext.save()

        let reader = WorkoutStatsReader(modelContainer: container)
        let texts = try await reader.bestSetTexts(weightTypes: [:], options: RecordsOptions())
        #expect(texts == [exerciseID: "100 kg × 5"])
        let names = try await reader.historySummary(weightTypes: [:], options: RecordsOptions()).entries.map(\.name)
        #expect(names == ["Pull"])
    }
}
