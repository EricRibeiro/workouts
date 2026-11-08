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
        let container = try makeTestContainer()
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
        let container = try makeTestContainer()
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

    @Test(arguments: [WeightUnit.kg, .lb])
    func workoutDetailEqualsTheSynchronousMake(unit: WeightUnit) async throws {
        let catalog = try Self.realCatalog()
        let store = ExerciseStore(catalog: catalog)
        let container = try seededContainer(catalog: catalog)
        let options = RecordsOptions(formula: .epley, displayUnit: unit)

        let finished = try container.mainContext.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.finishedAt != nil })
        )
        let target = try #require(finished.sorted { $0.startedAt < $1.startedAt }.last)
        let expected = try #require(
            WorkoutDetail.make(
                id: target.id,
                from: finished,
                weightType: { store.exercise(id: $0)?.weightType },
                options: options,
                now: Self.now
            )
        )
        let actual = try await WorkoutStatsReader.loadWorkoutDetail(
            in: container,
            id: target.id,
            weightTypes: store.weightTypes,
            options: options,
            now: Self.now
        )

        #expect(!expected.exercises.isEmpty)
        #expect(actual == expected)
    }

    @Test func workoutDetailIsNilForAnUnknownOrUnfinishedWorkout() async throws {
        let catalog = try Self.realCatalog()
        let container = try seededContainer(catalog: catalog)
        let open = try #require(
            container.mainContext.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.finishedAt == nil })).first
        )
        for id in [UUID(), open.id] {
            let detail = try await WorkoutStatsReader.loadWorkoutDetail(
                in: container,
                id: id,
                weightTypes: [:],
                options: RecordsOptions()
            )
            #expect(detail == nil)
        }
    }

    @Test func lastPerformedIndexEqualsTheSynchronousIndex() async throws {
        let catalog = try Self.realCatalog()
        let container = try seededContainer(catalog: catalog)
        let finished = try container.mainContext.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.finishedAt != nil })
        )
        let expected = TemplateCardSummary.LastPerformedIndex(finishedWorkouts: finished)
        let actual = try await WorkoutStatsReader.loadLastPerformedIndex(in: container)

        #expect(expected != TemplateCardSummary.LastPerformedIndex())
        #expect(actual == expected)
    }

    @Test func exerciseDetailEqualsTheSynchronousFold() async throws {
        let catalog = try Self.realCatalog()
        let store = ExerciseStore(catalog: catalog)
        let container = try seededContainer(catalog: catalog)
        let options = RecordsOptions(formula: .brzycki, displayUnit: .kg)
        let finished = try container.mainContext.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.finishedAt != nil })
        )
        let weightType = { (id: UUID) in store.exercise(id: id)?.weightType }
        let sessionsByExercise = ExerciseBestSets.sessions(from: finished, weightType: weightType)
        // The most-performed exercise, so the comparison is not trivial.
        let exerciseID = try #require(sessionsByExercise.max { $0.value.count < $1.value.count }?.key)
        let type = weightType(exerciseID) ?? .weighted

        let rows = try container.mainContext.fetch(ExerciseBestSets.rowsDescriptor(exerciseID: exerciseID))
        let sessions = ExerciseBestSets.sessions(forRows: rows, weightType: type)
        let expected = ExerciseDetailData(
            sessions: sessions,
            records: records(sessions, weightType: type, options: options),
            history: ExerciseHistory.sessions(
                sessions,
                names: ExerciseBestSets.workoutNames(of: rows),
                weightType: type,
                options: options
            )
        )
        let actual = try await WorkoutStatsReader.loadExerciseDetail(
            in: container,
            exerciseID: exerciseID,
            weightType: type,
            options: options
        )

        #expect(!expected.sessions.isEmpty)
        #expect(!expected.records.isEmpty)
        #expect(actual == expected)
        // The unfinished workout's row never counts.
        let unfinished = try await WorkoutStatsReader.loadExerciseDetail(
            in: container,
            exerciseID: catalog.exercises[0].id,
            weightType: .barbell,
            options: options
        )
        #expect(unfinished.sessions.flatMap(\.sets).allSatisfy { $0.weight != 500 })
    }
}
