import Foundation
import SQLite3
import SwiftData
import Testing

@testable import WorkoutsKit

// P-03 (2026-11-07 persistence review): every other schema test is in-memory, so nothing opened a real store written by
// an earlier build. `Fixtures/store-v1/Workouts.store` is a SQLite store written by the current `SchemaV1`; the test
// below opens a copy of it with `WorkoutsMigrationPlan`, as the app does on launch (V1 → V2 drops the sticky notes).
//
// ANY MODEL CHANGE MUST KEEP `OnDiskStoreMigrationTests` GREEN. A change SwiftData cannot infer (rename, type change,
// new required attribute without a default) needs a new `VersionedSchema` plus a migration stage in
// `WorkoutsMigrationPlan`; the fixture stays V1 and is migrated by those stages. Do not regenerate the fixture to make the
// test pass: that hides exactly the break this test exists to catch. Regenerate (see the generator below) only to extend
// what the fixture covers, and only against the schema the fixture is named for.

/// The values the fixture was generated with. The generator writes them; the test asserts them.
private enum Fixture {
    static let folderID = UUID(uuidString: "F0000000-0000-0000-0000-000000000001")!
    static let templateID = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!
    static let benchID = UUID(uuidString: "E0000000-0000-0000-0000-000000000001")!
    static let customID = UUID(uuidString: "E0000000-0000-0000-0000-000000000002")!
    static let noteID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
    static let firstWorkoutID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static let storeName = "Workouts.store"
}

@Suite struct OnDiskStoreMigrationTests {
    private func fixtureDirectory() throws -> URL {
        try #require(Bundle.module.url(forResource: "store-v1", withExtension: nil))
    }

    /// Copies the fixture into a fresh temp directory so opening it can never modify the committed files.
    private func copyFixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-v1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: try fixtureDirectory(), to: directory)
        return directory.appendingPathComponent(Fixture.storeName)
    }

    @Test func existingStoreOpensWithMigrationPlanAndKeepsItsData() throws {
        let url = try copyFixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try openMigrating(url)
        let context = ModelContext(container)

        func count<T: PersistentModel>(_ type: T.Type) throws -> Int { try context.fetchCount(FetchDescriptor<T>()) }
        #expect(try count(Exercise.self) == 1)
        #expect(try count(TemplateFolder.self) == 1)
        #expect(try count(Template.self) == 2)
        #expect(try count(TemplateExercise.self) == 2)
        #expect(try count(TemplateSet.self) == 3)
        #expect(try count(Workout.self) == 3)
        #expect(try count(WorkoutExercise.self) == 4)
        #expect(try count(WorkoutSet.self) == 8)

        let custom = try #require(try context.fetch(FetchDescriptor<Exercise>()).first)
        #expect(custom.id == Fixture.customID)
        #expect(custom.name == "Cable Crunch")
        #expect(custom.aliases == ["Rope Crunch"])
        #expect(custom.weightType == .machine)
        #expect(custom.unit == .kg)
        #expect(custom.barWeight == 17.25)
        #expect(custom.restSeconds == 75)

        let folder = try #require(try context.fetch(FetchDescriptor<TemplateFolder>()).first)
        #expect(folder.name == "Push Pull")
        #expect(folder.templates?.count == 1)

        let template = try #require(
            try context.fetch(FetchDescriptor<Template>(predicate: #Predicate { $0.name == "Push Day" })).first
        )
        #expect(template.id == Fixture.templateID)
        #expect(template.folder?.id == Fixture.folderID)
        #expect(template.exercises?.count == 2)
        #expect(template.workouts?.count == 2)

        let workouts = try context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(workouts.map(\.name) == ["Push A", "Push B", "In Progress"])
        let first = try #require(workouts.first)
        #expect(first.id == Fixture.firstWorkoutID)
        #expect(first.finishedAt == Fixture.start.addingTimeInterval(3_600))
        #expect(first.template?.id == Fixture.templateID)
        #expect(first.avgHeartRate == 128.5)
        #expect(first.healthWorkoutID == "HK-1")
        #expect(first.heartRateSeriesData == Data([1, 2, 3]))
        #expect(workouts[1].avgHeartRate == nil)
        let running = try #require(workouts.last)
        #expect(running.finishedAt == nil)
        #expect(running.restSeconds == 90)
        #expect(running.restEndsAt == Fixture.start.addingTimeInterval(5 * 86_400 + 60))

        let bench = try #require(first.exercises?.first { $0.exerciseID == Fixture.benchID })
        #expect(bench.exerciseName == "Bench Press")
        #expect(bench.unit == .kg)
        #expect(bench.barType == .olympic)
        #expect(bench.supersetGroup == 1)
        let sets = (bench.sets ?? []).sorted { $0.position < $1.position }
        #expect(sets.map(\.kind) == [.warmup, .normal, .normal])
        #expect(sets.map(\.weight) == [20, 80, 82.5])
        #expect(sets.map(\.reps) == [10, 5, 5])
        #expect(sets.map(\.completed) == [true, true, false])
        #expect(sets[1].rpe == 8)

        // The migrated store is also writable: the app saves straight after launch.
        context.insert(Exercise(name: "After open"))
        try context.save()
        #expect(try count(Exercise.self) == 2)
    }

    @Test func v1StoreWithAStickyNoteMigratesToV2DroppingTheEntity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-v1-written-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(Fixture.storeName)

        // Written the way a TestFlight build wrote it: SchemaV1, no migration plan, a sticky note among the rows.
        do {
            let container = try openV1(url)
            let context = ModelContext(container)
            populate(context)
            try context.save()
            #expect(try context.fetchCount(FetchDescriptor<StickyNote>()) == 1)
        }

        let container = try openMigrating(url)
        let context = ModelContext(container)
        #expect(!container.schema.entities.contains { $0.name == "StickyNote" })
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TemplateFolder>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Template>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<TemplateExercise>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<TemplateSet>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutExercise>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSet>()) == 8)
    }

    /// Opens `url` as the app does: the V2 schema through `WorkoutsMigrationPlan`.
    private func openMigrating(_ url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: WorkoutsMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        )
    }

    /// Opens `url` with the V1 schema alone, which is how a V1 store comes to exist.
    private func openV1(_ url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        )
    }

    // MARK: Generator

    /// Rebuilds `Fixtures/store-v1/` from the CURRENT models. Off by default so `./dev kit` never rewrites the fixture:
    /// run `GENERATE_STORE_FIXTURE=1 ./dev kit OnDiskStoreMigrationTests/regenerateFixture`. Only do this while `SchemaV1`
    /// is still the schema the fixture stands for; see the note at the top of this file.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GENERATE_STORE_FIXTURE"] == "1"))
    func regenerateFixture() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/store-v1", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Fixture.storeName)

        do {
            let container = try openV1(url)
            let context = ModelContext(container)
            populate(context)
            try context.save()
        }

        // Fold the write-ahead log into the main file so the fixture is the single committed `.store`.
        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        try #require(sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil) == SQLITE_OK)
        try #require(sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil) == SQLITE_OK)
        for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }

    private func populate(_ context: ModelContext) {
        let start = Fixture.start
        context.insert(
            Exercise(
                id: Fixture.customID,
                name: "Cable Crunch",
                aliases: ["Rope Crunch"],
                equipment: ["cable"],
                bodyPart: "core",
                weightType: .machine,
                instructions: ["Crunch down"],
                unit: .kg,
                barType: .none,
                barWeight: 17.25,
                restSeconds: 75,
                createdAt: start,
                updatedAt: start
            )
        )
        context.insert(
            StickyNote(
                id: Fixture.noteID,
                exerciseID: Fixture.benchID,
                text: "Elbows tucked, pause on the chest",
                updatedAt: start
            )
        )

        let folder = TemplateFolder(
            id: Fixture.folderID,
            name: "Push Pull",
            position: 0,
            createdAt: start,
            updatedAt: start
        )
        context.insert(folder)
        let push = Template(
            id: Fixture.templateID,
            name: "Push Day",
            note: "Chest first",
            position: 0,
            folder: folder,
            createdAt: start,
            updatedAt: start
        )
        let loose = Template(name: "Legs", position: 1, createdAt: start, updatedAt: start)
        context.insert(push)
        context.insert(loose)
        let templateBench = TemplateExercise(
            exerciseID: Fixture.benchID,
            exerciseName: "Bench Press",
            position: 0,
            unit: .kg,
            template: push
        )
        let templateCrunch = TemplateExercise(
            exerciseID: Fixture.customID,
            exerciseName: "Cable Crunch",
            position: 1,
            unit: .kg,
            template: push
        )
        context.insert(templateBench)
        context.insert(templateCrunch)
        for position in 0..<2 {
            context.insert(TemplateSet(position: position, weight: 80, reps: 5, templateExercise: templateBench))
        }
        context.insert(TemplateSet(position: 0, weight: 20, reps: 15, templateExercise: templateCrunch))

        func addWorkout(id: UUID = UUID(), name: String, day: Int, finished: Bool, template: Template?) -> Workout {
            let began = start.addingTimeInterval(TimeInterval(day) * 86_400)
            let workout = Workout(
                id: id,
                name: name,
                startedAt: began,
                finishedAt: finished ? began.addingTimeInterval(3_600) : nil,
                template: template,
                createdAt: began,
                updatedAt: began
            )
            context.insert(workout)
            return workout
        }
        let first = addWorkout(id: Fixture.firstWorkoutID, name: "Push A", day: 0, finished: true, template: push)
        first.healthWorkoutID = "HK-1"
        first.avgHeartRate = 128.5
        first.heartRateSeriesData = Data([1, 2, 3])
        let second = addWorkout(name: "Push B", day: 3, finished: true, template: push)
        let running = addWorkout(name: "In Progress", day: 5, finished: false, template: nil)
        running.restSeconds = 90
        running.restEndsAt = start.addingTimeInterval(5 * 86_400 + 60)

        let bench = WorkoutExercise(
            exerciseID: Fixture.benchID,
            exerciseName: "Bench Press",
            position: 0,
            supersetGroup: 1,
            unit: .kg,
            workout: first
        )
        let crunch = WorkoutExercise(
            exerciseID: Fixture.customID,
            exerciseName: "Cable Crunch",
            position: 1,
            unit: .kg,
            workout: first
        )
        let benchAgain = WorkoutExercise(
            exerciseID: Fixture.benchID,
            exerciseName: "Bench Press",
            position: 0,
            unit: .kg,
            workout: second
        )
        let benchRunning = WorkoutExercise(
            exerciseID: Fixture.benchID,
            exerciseName: "Bench Press",
            position: 0,
            unit: .kg,
            workout: running
        )
        for exercise in [bench, crunch, benchAgain, benchRunning] { context.insert(exercise) }
        context.insert(
            WorkoutSet(position: 0, kind: .warmup, weight: 20, reps: 10, completed: true, workoutExercise: bench)
        )
        context.insert(WorkoutSet(position: 1, weight: 80, reps: 5, completed: true, rpe: 8, workoutExercise: bench))
        context.insert(WorkoutSet(position: 2, weight: 82.5, reps: 5, completed: false, workoutExercise: bench))
        context.insert(WorkoutSet(position: 0, weight: 25, reps: 15, completed: true, workoutExercise: crunch))
        context.insert(WorkoutSet(position: 0, weight: 82.5, reps: 5, completed: true, workoutExercise: benchAgain))
        context.insert(WorkoutSet(position: 1, weight: 82.5, reps: 4, completed: true, workoutExercise: benchAgain))
        context.insert(WorkoutSet(position: 0, weight: 85, reps: 3, completed: true, workoutExercise: benchRunning))
        context.insert(WorkoutSet(position: 1, weight: 85, workoutExercise: benchRunning))
    }
}
