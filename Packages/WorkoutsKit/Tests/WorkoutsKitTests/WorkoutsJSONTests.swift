import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct ImportTests {
    // MARK: Fixtures

    /// Whole-and-quarter seconds, so dates survive the millisecond JSON encoding exactly.
    private static func t(_ seconds: Double) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + seconds)
    }

    private static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n)) ?? UUID()
    }

    private static let source = "smartworkout"

    /// A catalog of two library exercises ("100", "101").
    private static func catalog() throws -> LibraryCatalog {
        func entry(_ sourceID: String, _ name: String) -> String {
            """
            {"id": "\(LibraryID.id(source: source, sourceID: sourceID).uuidString)", "source": "\(source)",
             "sourceId": "\(sourceID)", "name": "\(name)", "bodyPart": "chest", "weightType": "barbell"}
            """
        }
        let json = """
            {"version": 1, "exercises": [\(entry("100", "Bench Press")), \(entry("101", "Overhead Press"))]}
            """
        return try LibraryCatalog(data: Data(json.utf8))
    }

    private static func realCatalog() throws -> LibraryCatalog {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try LibraryCatalog(
            data: Data(contentsOf: repoRoot.appendingPathComponent("Resources/Library/library.json"))
        )
    }

    /// One folder, two templates, a custom exercise, a sticky note, a finished and an in-progress
    /// workout. Ordered the way `Exporter` orders its output, so an export equals it.
    private static func fixture() -> WorkoutsJSON {
        let bench = ExerciseRefDTO.library(source: source, sourceId: "100")
        let press = ExerciseRefDTO.library(source: source, sourceId: "101")
        let sled = ExerciseRefDTO.custom(id: id(900))

        let folder = FolderDTO(id: id(1), name: "Splits", position: 0, createdAt: t(0), updatedAt: t(1))
        let push = TemplateDTO(
            id: id(10),
            name: "Push",
            note: "Heavy day",
            position: 0,
            folderId: id(1),
            createdAt: t(0),
            updatedAt: t(2),
            exercises: [
                TemplateExerciseDTO(
                    id: id(11),
                    exercise: bench,
                    exerciseName: "Bench Press",
                    position: 0,
                    supersetGroup: nil,
                    note: "Pause",
                    restSeconds: 120,
                    unit: .lb,
                    barType: .olympic,
                    barWeight: 45,
                    updatedAt: t(2),
                    sets: [
                        TemplateSetDTO(
                            id: id(12),
                            position: 0,
                            kind: .warmup,
                            weight: 95,
                            reps: 10,
                            durationSeconds: nil,
                            distanceMeters: nil
                        ),
                        TemplateSetDTO(
                            id: id(13),
                            position: 1,
                            kind: .normal,
                            weight: 135.5,
                            reps: 8,
                            durationSeconds: nil,
                            distanceMeters: nil
                        ),
                    ]
                ),
                TemplateExerciseDTO(
                    id: id(14),
                    exercise: sled,
                    exerciseName: "Sled Push",
                    position: 1,
                    supersetGroup: 1,
                    note: "",
                    restSeconds: nil,
                    unit: .kg,
                    barType: .none,
                    barWeight: nil,
                    updatedAt: t(2),
                    sets: [
                        TemplateSetDTO(
                            id: id(15),
                            position: 0,
                            kind: .normal,
                            weight: nil,
                            reps: nil,
                            durationSeconds: 30,
                            distanceMeters: 20
                        )
                    ]
                ),
            ]
        )
        let empty = TemplateDTO(
            id: id(20),
            name: "Empty",
            note: "",
            position: 1,
            folderId: nil,
            createdAt: t(0),
            updatedAt: t(3),
            exercises: []
        )
        let custom = CustomExerciseDTO(
            id: id(900),
            name: "Sled Push",
            aliases: ["Prowler"],
            equipment: ["sled"],
            bodyPart: "legs",
            weightType: .weighted,
            instructions: ["Drive"],
            unit: .kg,
            barType: .none,
            barWeight: nil,
            restSeconds: 90,
            retired: false,
            createdAt: t(0),
            updatedAt: t(4)
        )
        let note = StickyNoteDTO(id: id(30), exercise: bench, text: "Elbows in", updatedAt: t(5))
        let finished = WorkoutDTO(
            id: id(40),
            name: "Push",
            note: "Felt good",
            startedAt: t(10),
            finishedAt: t(3_610),
            templateId: id(10),
            createdAt: t(10),
            updatedAt: t(3_610),
            restEndsAt: nil,
            restSeconds: nil,
            restSetId: nil,
            exercises: [
                WorkoutExerciseDTO(
                    id: id(41),
                    exercise: press,
                    exerciseName: "Overhead Press",
                    position: 0,
                    supersetGroup: nil,
                    note: "",
                    restSeconds: 90,
                    unit: .lb,
                    barType: .olympic,
                    barWeight: 45,
                    updatedAt: t(3_610),
                    sets: [
                        WorkoutSetDTO(
                            id: id(42),
                            position: 0,
                            kind: .normal,
                            weight: 95,
                            reps: 8,
                            durationSeconds: nil,
                            distanceMeters: nil,
                            completed: true,
                            completedAt: t(100),
                            rpe: 8.5
                        ),
                        WorkoutSetDTO(
                            id: id(43),
                            position: 1,
                            kind: .failure,
                            weight: 95,
                            reps: 6,
                            durationSeconds: nil,
                            distanceMeters: nil,
                            completed: true,
                            completedAt: t(200),
                            rpe: nil
                        ),
                    ]
                )
            ]
        )
        let active = WorkoutDTO(
            id: id(50),
            name: "Active",
            note: "",
            startedAt: t(7_200),
            finishedAt: nil,
            templateId: nil,
            createdAt: t(7_200),
            updatedAt: t(7_300),
            restEndsAt: t(7_400),
            restSeconds: 120,
            restSetId: id(52),
            exercises: [
                WorkoutExerciseDTO(
                    id: id(51),
                    exercise: sled,
                    exerciseName: "Sled Push",
                    position: 0,
                    supersetGroup: nil,
                    note: "",
                    restSeconds: nil,
                    unit: .kg,
                    barType: .none,
                    barWeight: nil,
                    updatedAt: t(7_300),
                    sets: [
                        WorkoutSetDTO(
                            id: id(52),
                            position: 0,
                            kind: .normal,
                            weight: 40,
                            reps: nil,
                            durationSeconds: 25,
                            distanceMeters: 20,
                            completed: false,
                            completedAt: nil,
                            rpe: nil
                        )
                    ]
                )
            ]
        )
        return WorkoutsJSON(
            exportedAt: t(10_000),
            folders: [folder],
            templates: [push, empty],
            customExercises: [custom],
            stickyNotes: [note],
            workouts: [finished, active]
        )
    }

    private struct Store {
        let container: ModelContainer
        var context: ModelContext { container.mainContext }

        init() throws {
            container = try makeTestContainer()
        }

        func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
            try context.fetchCount(FetchDescriptor<T>())
        }
    }

    /// The document with `exportedAt` pinned, so two exports compare equal.
    private static func pinned(_ doc: WorkoutsJSON) -> WorkoutsJSON {
        var copy = doc
        copy.exportedAt = t(10_000)
        return copy
    }

    // MARK: Codec

    @Test func encodeDecodeRoundTripsTheDocument() throws {
        let doc = Self.fixture()
        let data = try doc.encoded()
        #expect(try WorkoutsJSON.decode(data) == doc)
        #expect(try WorkoutsJSON.decoder.decode(WorkoutsJSON.self, from: WorkoutsJSON.encoder.encode(doc)) == doc)
    }

    @Test func encoderIsDeterministicAndWritesFractionalIsoDates() throws {
        let doc = Self.fixture()
        let first = try doc.encoded()
        #expect(try doc.encoded() == first)
        let text = String(decoding: first, as: UTF8.self)
        #expect(text.contains("\"exportedAt\":\"2027-01-15T10:46:40.000Z\""))
        // Sorted keys: "customExercises" precedes "exportedAt" precedes "folders".
        let custom = try #require(text.range(of: "\"customExercises\""))
        let exported = try #require(text.range(of: "\"exportedAt\""))
        let folders = try #require(text.range(of: "\"folders\""))
        #expect(custom.lowerBound < exported.lowerBound && exported.lowerBound < folders.lowerBound)
    }

    @Test func decoderAcceptsDatesWithoutFractionsAndMissingArrays() throws {
        let json = #"{"version": 1, "exportedAt": "2027-01-15T08:00:00Z"}"#
        let doc = try WorkoutsJSON.decode(Data(json.utf8))
        #expect(doc.exportedAt == Self.t(0))
        #expect(doc.folders.isEmpty && doc.templates.isEmpty && doc.workouts.isEmpty)
        #expect(doc.customExercises.isEmpty && doc.stickyNotes.isEmpty)
        let bad = #"{"version": 1, "exportedAt": "yesterday"}"#
        #expect(throws: DecodingError.self) { try WorkoutsJSON.decode(Data(bad.utf8)) }
    }

    @Test func exerciseRefCodesBothFormsAndRejectsEmpty() throws {
        let library = ExerciseRefDTO.library(source: Self.source, sourceId: "100")
        let custom = ExerciseRefDTO.custom(id: Self.id(7))
        for ref in [library, custom] {
            let data = try WorkoutsJSON.encoder.encode(ref)
            #expect(try WorkoutsJSON.decoder.decode(ExerciseRefDTO.self, from: data) == ref)
        }
        #expect(
            String(decoding: try WorkoutsJSON.encoder.encode(library), as: UTF8.self)
                == #"{"source":"smartworkout","sourceId":"100"}"#
        )
        #expect(library.exerciseID == LibraryID.id(source: Self.source, sourceID: "100"))
        #expect(custom.exerciseID == Self.id(7))
        #expect(throws: DecodingError.self) {
            try WorkoutsJSON.decoder.decode(ExerciseRefDTO.self, from: Data("{}".utf8))
        }
    }

    // MARK: Export and import

    @Test func importIntoAnEmptyStoreInsertsEverythingAndExportsBack() throws {
        let doc = Self.fixture()
        let catalog = try Self.catalog()
        let store = try Store()

        let report = try Importer.apply(doc, to: store.context, catalog: catalog)

        #expect(report[.folders] == ImportCounts(inserted: 1))
        #expect(report[.templates] == ImportCounts(inserted: 2))
        #expect(report[.templateExercises] == ImportCounts(inserted: 2))
        #expect(report[.templateSets] == ImportCounts(inserted: 3))
        #expect(report[.customExercises] == ImportCounts(inserted: 1))
        #expect(report[.stickyNotes] == ImportCounts(inserted: 1))
        #expect(report[.workouts] == ImportCounts(inserted: 2))
        #expect(report[.workoutExercises] == ImportCounts(inserted: 2))
        #expect(report[.workoutSets] == ImportCounts(inserted: 3))
        #expect(report.totals.inserted == 17)
        #expect(report.changedAnything)
        #expect(report.unknownLibraryRefs.isEmpty && report.danglingReferences == 0)

        #expect(try store.count(Workout.self) == 2)
        #expect(try store.count(WorkoutSet.self) == 3)
        #expect(try store.count(TemplateSet.self) == 3)

        let exported = try Exporter.document(from: store.context, catalog: catalog, exportedAt: Self.t(10_000))
        #expect(exported == doc)
    }

    @Test func exportWritesIdsForEveryReferenceWithoutACatalog() throws {
        let store = try Store()
        _ = try Importer.apply(Self.fixture(), to: store.context)
        let exported = try Exporter.document(from: store.context)
        let refs = exported.templates.flatMap(\.exercises).map(\.exercise)
        #expect(refs.count == 2)
        #expect(
            refs.contains(.custom(id: LibraryID.id(source: Self.source, sourceID: "100")))
        )
        #expect(refs.allSatisfy { if case .custom = $0 { true } else { false } })
    }

    @Test func importedFieldValuesAndRelationshipsMatchTheDocument() throws {
        let store = try Store()
        _ = try Importer.apply(Self.fixture(), to: store.context, catalog: try Self.catalog())
        let context = store.context

        let templates = try context.fetch(FetchDescriptor<Template>(sortBy: [SortDescriptor(\.position)]))
        let push = try #require(templates.first)
        #expect(push.name == "Push" && push.note == "Heavy day")
        #expect(push.folder?.name == "Splits")
        #expect(templates[1].folder == nil)
        let bench = try #require(push.exercises?.first { $0.position == 0 })
        #expect(bench.exerciseID == LibraryID.id(source: Self.source, sourceID: "100"))
        #expect(bench.exerciseName == "Bench Press" && bench.restSeconds == 120)
        #expect(bench.template?.id == push.id)
        let sets = (bench.sets ?? []).sorted { $0.position < $1.position }
        #expect(sets.map(\.kind) == [.warmup, .normal])
        #expect(sets.map(\.weight) == [95, 135.5])

        let workouts = try context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(workouts.map(\.name) == ["Push", "Active"])
        #expect(workouts[0].template?.id == push.id)
        #expect(workouts[0].finishedAt == Self.t(3_610))
        #expect(workouts[1].finishedAt == nil && workouts[1].template == nil)
        #expect(workouts[1].restSetID == Self.id(52) && workouts[1].restSeconds == 120)
        let done = try #require(workouts[0].exercises?.first?.sets?.first { $0.position == 0 })
        #expect(done.completed && done.rpe == 8.5 && done.completedAt == Self.t(100))

        let custom = try #require(try context.fetch(FetchDescriptor<Exercise>()).first)
        #expect(custom.id == Self.id(900) && custom.aliases == ["Prowler"] && custom.weightType == .weighted)
        let sticky = try #require(try context.fetch(FetchDescriptor<StickyNote>()).first)
        #expect(sticky.exerciseID == LibraryID.id(source: Self.source, sourceID: "100"))
    }

    // MARK: Idempotence

    @Test func importingTheSameDocumentTwiceChangesNothing() throws {
        let doc = Self.fixture()
        let catalog = try Self.catalog()
        let store = try Store()
        _ = try Importer.apply(doc, to: store.context, catalog: catalog)
        let before = try Exporter.document(from: store.context, catalog: catalog, exportedAt: Self.t(10_000))

        let second = try Importer.apply(doc, to: store.context, catalog: catalog)

        #expect(second.totals.inserted == 0 && second.totals.updated == 0 && second.totals.removed == 0)
        #expect(second.changedAnything == false)
        #expect(second[.folders] == ImportCounts(skipped: 1))
        #expect(second[.templates] == ImportCounts(skipped: 2))
        #expect(second[.templateSets] == ImportCounts(skipped: 3))
        #expect(second[.customExercises] == ImportCounts(skipped: 1))
        #expect(second[.stickyNotes] == ImportCounts(skipped: 1))
        #expect(second[.workouts] == ImportCounts(skipped: 2))
        #expect(second[.workoutExercises] == ImportCounts(skipped: 2))
        #expect(second[.workoutSets] == ImportCounts(skipped: 3))
        #expect(try store.count(Workout.self) == 2)
        #expect(try store.count(WorkoutExercise.self) == 2)
        #expect(try store.count(TemplateExercise.self) == 2)
        #expect(try store.count(StickyNote.self) == 1)
        let after = try Exporter.document(from: store.context, catalog: catalog, exportedAt: Self.t(10_000))
        #expect(after == before)
    }

    // MARK: In-progress workout

    private static func engine(for store: Store) throws -> ActiveWorkoutEngine {
        try ActiveWorkoutEngine(
            context: store.context,
            store: ExerciseStore(catalog: try catalog(), custom: []),
            settings: SettingsStore(backend: InMemoryBackend()),
            now: { t(8_000) }
        )
    }

    @Test func anUnfinishedWorkoutIsSkippedWhileAnotherIsInProgress() throws {
        let store = try Store()
        let engine = try Self.engine(for: store)
        let running = try engine.startEmpty()
        let runningID = running.id

        let report = try Importer.apply(Self.fixture(), to: store.context, catalog: try Self.catalog())

        #expect(report.skippedInProgress == 1)
        #expect(report[.workouts] == ImportCounts(inserted: 1, skipped: 1))
        #expect(report.summary.contains("1 unfinished workout was skipped because one is in progress."))
        let unfinished = try store.context.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.finishedAt == nil })
        )
        #expect(unfinished.map(\.id) == [runningID])
        #expect(try engine.resume()?.id == runningID)
        #expect(try store.count(WorkoutExercise.self) == 1)
    }

    @Test func anUnfinishedWorkoutIsImportedWhenNoneIsRunningAndTheEngineResumesIt() throws {
        let store = try Store()
        let engine = try Self.engine(for: store)
        #expect(engine.workout == nil)

        let report = try Importer.apply(Self.fixture(), to: store.context, catalog: try Self.catalog())

        #expect(report.skippedInProgress == 0)
        #expect(report[.workouts] == ImportCounts(inserted: 2))
        let resumed = try #require(try engine.resume())
        #expect(resumed.id == Self.id(50))
        #expect(engine.workout?.id == Self.id(50))
    }

    @Test func reimportingTheEnginesOwnMidWorkoutExportIsANoOp() throws {
        let store = try Store()
        let engine = try Self.engine(for: store)
        let running = try engine.startEmpty()
        let exported = try Exporter.document(
            from: store.context,
            catalog: try Self.catalog(),
            exportedAt: Self.t(10_000)
        )
        #expect(exported.workouts.map(\.id) == [running.id])

        let report = try Importer.apply(exported, to: store.context, catalog: try Self.catalog())

        #expect(report.changedAnything == false)
        #expect(report.skippedInProgress == 0)
        #expect(report[.workouts] == ImportCounts(skipped: 1))
        #expect(try store.count(Workout.self) == 1)
    }

    @Test func aNewerRowWinsAndReplacesItsChildren() throws {
        var doc = Self.fixture()
        let store = try Store()
        _ = try Importer.apply(doc, to: store.context)

        // Edit the finished workout: rename, drop a set, add an exercise with a set.
        doc.workouts[0].name = "Push (edited)"
        doc.workouts[0].updatedAt = Self.t(9_000)
        doc.workouts[0].exercises[0].sets.removeLast()
        doc.workouts[0].exercises[0].sets[0].reps = 10
        let added = WorkoutExerciseDTO(
            id: Self.id(60),
            exercise: .library(source: Self.source, sourceId: "100"),
            exerciseName: "Bench Press",
            position: 1,
            supersetGroup: nil,
            note: "",
            restSeconds: nil,
            unit: .lb,
            barType: .olympic,
            barWeight: 45,
            updatedAt: Self.t(9_000),
            sets: [
                WorkoutSetDTO(
                    id: Self.id(61),
                    position: 0,
                    kind: .normal,
                    weight: 100,
                    reps: 5,
                    durationSeconds: nil,
                    distanceMeters: nil,
                    completed: true,
                    completedAt: nil,
                    rpe: nil
                )
            ]
        )
        doc.workouts[0].exercises.append(added)

        let report = try Importer.apply(doc, to: store.context)

        #expect(report[.workouts] == ImportCounts(updated: 1, skipped: 1))
        #expect(report[.workoutExercises] == ImportCounts(inserted: 1, updated: 1, skipped: 1))
        #expect(report[.workoutSets] == ImportCounts(inserted: 1, updated: 1, skipped: 1, removed: 1))
        #expect(try store.count(Workout.self) == 2)
        #expect(try store.count(WorkoutSet.self) == 3)
        let exported = try Exporter.document(from: store.context, exportedAt: Self.t(10_000))
        #expect(exported.workouts[0].name == "Push (edited)")
        #expect(exported.workouts[0].exercises.map(\.id) == [Self.id(41), Self.id(60)])
        #expect(exported.workouts[0].exercises[0].sets.map(\.reps) == [10])
    }

    @Test func anOlderRowLosesAndLeavesItsChildren() throws {
        var doc = Self.fixture()
        let store = try Store()
        _ = try Importer.apply(doc, to: store.context)

        doc.workouts[0].name = "Stale"
        doc.workouts[0].updatedAt = Self.t(-5)
        doc.workouts[0].exercises[0].sets.removeAll()
        doc.templates[0].name = "Stale template"
        doc.templates[0].updatedAt = Self.t(-5)
        doc.templates[0].exercises.removeAll()

        let report = try Importer.apply(doc, to: store.context)

        #expect(report.totals.inserted == 0 && report.totals.updated == 0 && report.totals.removed == 0)
        #expect(report[.workouts].skipped == 2 && report[.templates].skipped == 2)
        #expect(try store.count(WorkoutSet.self) == 3)
        #expect(try store.count(TemplateExercise.self) == 2)
        let exported = try Exporter.document(from: store.context, exportedAt: Self.t(10_000))
        #expect(exported.workouts[0].name == "Push")
        #expect(exported.templates[0].name == "Push")
    }

    @Test func aStickyNoteForTheSameExerciseUpdatesEvenWithANewId() throws {
        var doc = Self.fixture()
        let store = try Store()
        _ = try Importer.apply(doc, to: store.context)

        doc.stickyNotes[0].id = Self.id(31)
        doc.stickyNotes[0].text = "Newer text"
        doc.stickyNotes[0].updatedAt = Self.t(500)
        let report = try Importer.apply(doc, to: store.context)

        #expect(report[.stickyNotes] == ImportCounts(updated: 1))
        #expect(try store.count(StickyNote.self) == 1)
        #expect(try store.context.fetch(FetchDescriptor<StickyNote>()).first?.text == "Newer text")
    }

    @Test func aTemplateMovesBetweenFoldersAndDanglingIdsAreCounted() throws {
        var doc = Self.fixture()
        let store = try Store()
        _ = try Importer.apply(doc, to: store.context)

        doc.templates[0].folderId = nil
        doc.templates[0].updatedAt = Self.t(600)
        doc.workouts[0].templateId = Self.id(12_345)
        doc.workouts[0].updatedAt = Self.t(20_000)
        let report = try Importer.apply(doc, to: store.context)

        #expect(report.danglingReferences == 1)
        let push = try #require(try store.context.fetch(FetchDescriptor<Template>()).first { $0.name == "Push" })
        #expect(push.folder == nil)
        #expect(try store.context.fetch(FetchDescriptor<Workout>()).first { $0.name == "Push" }?.template == nil)
    }

    // MARK: Library references

    @Test func anUnknownLibraryReferenceIsReportedAndKeepsItsNameSnapshot() throws {
        var doc = Self.fixture()
        let mystery = ExerciseRefDTO.library(source: Self.source, sourceId: "999")
        doc.templates[0].exercises[0].exercise = mystery
        doc.templates[0].exercises[0].exerciseName = "Mystery Lift"
        doc.workouts[0].exercises[0].exercise = mystery
        doc.workouts[0].exercises[0].exerciseName = "Mystery Lift"
        doc.stickyNotes[0].exercise = mystery
        let store = try Store()

        let report = try Importer.apply(doc, to: store.context, catalog: try Self.catalog())

        #expect(
            report.unknownLibraryRefs == [
                UnknownLibraryRef(source: Self.source, sourceId: "999", names: ["Mystery Lift"], uses: 3)
            ]
        )
        #expect(report[.templateExercises].inserted == 2 && report[.workoutExercises].inserted == 2)
        let row = try #require(
            try store.context.fetch(FetchDescriptor<TemplateExercise>()).first { $0.exerciseName == "Mystery Lift" }
        )
        #expect(row.exerciseID == LibraryID.id(source: Self.source, sourceID: "999"))
    }

    @Test func aLibraryReferenceMapsToItsLibraryIDAndIsNotReported() throws {
        let catalog = try Self.catalog()
        let store = try Store()
        let report = try Importer.apply(Self.fixture(), to: store.context, catalog: catalog)

        #expect(report.unknownLibraryRefs.isEmpty)
        let expected = LibraryID.id(source: Self.source, sourceID: "101")
        #expect(catalog.exercise(id: expected)?.sourceId == "101")
        let workoutExercises = try store.context.fetch(FetchDescriptor<WorkoutExercise>())
        #expect(workoutExercises.contains { $0.exerciseID == expected && $0.exerciseName == "Overhead Press" })
    }

    @Test func withoutACatalogNothingIsReportedUnknown() throws {
        var doc = Self.fixture()
        doc.templates[0].exercises[0].exercise = .library(source: "other", sourceId: "1")
        let store = try Store()
        let report = try Importer.apply(doc, to: store.context)
        #expect(report.unknownLibraryRefs.isEmpty)
        #expect(report[.templateExercises].inserted == 2)
    }

    // MARK: Guards and scale

    @Test func anUnsupportedVersionIsRefusedBeforeTouchingTheStore() throws {
        var doc = Self.fixture()
        doc.version = 2
        let store = try Store()
        #expect(throws: ImportError.unsupportedVersion(2)) {
            try Importer.apply(doc, to: store.context)
        }
        #expect(try store.count(Workout.self) == 0)
    }

    @Test func fitnessDataThatCannotBeStoredFailsTheImportAndRollsBack() throws {
        var doc = Self.fixture()
        doc.workouts[0].healthWorkoutId = "HK-1"
        doc.workouts[0].heartRateSeries = [HeartRatePoint(offset: 0, bpm: .nan)]
        let store = try Store()
        #expect(throws: ImportError.unstorableHealthData("heartRateSeries")) {
            try Importer.apply(doc, to: store.context)
        }
        #expect(try store.count(Workout.self) == 0)
        #expect(try store.count(Template.self) == 0)
        #expect(ImportError.unstorableHealthData("heartRateSeries").localizedDescription.contains("heartRateSeries"))
    }

    @Test func anEmptyDocumentImportsNothing() throws {
        let store = try Store()
        let report = try Importer.apply(WorkoutsJSON(), to: store.context)
        #expect(report.totals == ImportCounts())
        #expect(report.changedAnything == false)
        #expect(report[.workouts] == ImportCounts())
        #expect(try Exporter.document(from: store.context).workouts.isEmpty)
    }

    @Test func sampleDataSurvivesExportEncodeDecodeImport() throws {
        let catalog = try Self.realCatalog()
        let source = try Store()
        try SampleData.seed(into: source.context, catalog: catalog, now: Self.t(0), seed: 1)
        let exported = try Exporter.document(from: source.context, catalog: catalog, exportedAt: Self.t(10_000))
        #expect(exported.workouts.count == SampleData.finishedWorkoutCount)
        let customID = try #require(exported.customExercises.first?.id)
        let refs =
            (exported.templates.flatMap(\.exercises).map(\.exercise))
            + exported.workouts.flatMap(\.exercises).map(\.exercise)
        #expect(
            refs.allSatisfy { ref in
                switch ref {
                case .library: true
                case .custom(let id): id == customID
                }
            }
        )

        let decoded = try WorkoutsJSON.decode(try exported.encoded())
        let target = try Store()
        let report = try Importer.apply(decoded, to: target.context, catalog: catalog)
        #expect(report.unknownLibraryRefs.isEmpty && report.danglingReferences == 0)
        #expect(report[.workouts].inserted == SampleData.finishedWorkoutCount)

        let reexported = try Exporter.document(from: target.context, catalog: catalog, exportedAt: Self.t(10_000))
        #expect(try reexported.encoded() == exported.encoded())

        let again = try Importer.apply(decoded, to: target.context, catalog: catalog)
        #expect(again.totals.inserted == 0 && again.totals.updated == 0 && again.totals.removed == 0)
    }
}
