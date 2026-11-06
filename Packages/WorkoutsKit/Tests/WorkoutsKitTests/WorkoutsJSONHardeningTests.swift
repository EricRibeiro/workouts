import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

/// The importer against hostile or hand-edited files (review 3c): nothing in a file may crash a later screen, move
/// another parent's rows, or override the library.
@Suite struct ImportHardeningTests {
    // MARK: Fixtures

    private static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n)) ?? UUID()
    }

    private static let start = "2026-01-01T10:00:00Z"
    private static let end = "2026-01-01T11:00:00Z"

    private static func set(_ n: Int, position: Int = 0) -> String {
        """
        {"id":"\(id(n))","position":\(position),"kind":"normal","weight":100,"reps":5,"durationSeconds":null,
         "distanceMeters":null,"completed":true,"completedAt":"2026-01-01T10:10:00Z","rpe":null}
        """
    }

    private static func exercise(_ n: Int, sets: [String], position: Int = 0, group: String = "null") -> String {
        """
        {"id":"\(id(n))","exercise":{"id":"\(id(999))"},"exerciseName":"X","position":\(position),
         "supersetGroup":\(group),"note":"","restSeconds":null,"unit":"lb","barType":"olympic","barWeight":null,
         "updatedAt":"2026-01-01T10:00:00Z","sets":[\(sets.joined(separator: ","))]}
        """
    }

    private static func workout(
        _ n: Int,
        finished: String? = end,
        started: String = start,
        updated: String = "2026-01-01T11:00:00Z",
        health: String = "",
        exercises: [String] = []
    ) -> String {
        let finishedText = finished.map { "\"\($0)\"" } ?? "null"
        return """
            {"id":"\(id(n))","name":"W","note":"","startedAt":"\(started)","finishedAt":\(finishedText),
             "templateId":null,"createdAt":"2026-01-01T10:00:00Z","updatedAt":"\(updated)","restEndsAt":null,
             "restSeconds":null,"restSetId":null,\(health)"exercises":[\(exercises.joined(separator: ","))]}
            """
    }

    private static func template(_ n: Int, position: Int, exercises: [String] = []) -> String {
        """
        {"id":"\(id(n))","name":"T\(n)","note":"","position":\(position),"folderId":null,
         "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z","exercises":[\(exercises.joined(separator: ","))]}
        """
    }

    private static func text(version: Int = 1, extra: String = "", workouts: [String] = []) -> String {
        """
        {"version":\(version),"exportedAt":"2026-01-01T00:00:00Z",\(extra)"workouts":[\(workouts.joined(separator: ","))]}
        """
    }

    private static func document(extra: String = "", workouts: [String] = []) throws -> WorkoutsJSON {
        try WorkoutsJSON.decode(Data(text(extra: extra, workouts: workouts).utf8))
    }

    private static func fetch<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    // MARK: 1. Positions and superset numbers

    @Test func anIntMaxFolderPositionDoesNotTrapLaterOperations() throws {
        let context = try makeTestContext()
        let folders = """
            "folders":[{"id":"\(Self.id(7))","name":"F","position":9223372036854775807,
            "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}],
            """
        _ = try Importer.apply(try Self.document(extra: folders), to: context)
        let created = try FolderOperations.create(named: "New", in: context)
        #expect(try Self.fetch(TemplateFolder.self, in: context).map(\.position).sorted() == [0, 1])
        #expect(created?.position == 1)
    }

    @Test func positionsAndSupersetGroupsAreRenumberedPerParent() throws {
        let context = try makeTestContext()
        let max = "9223372036854775807"
        let templates = """
            "templates":[\(Self.template(1, position: Int.max, exercises: [Self.exercise(20, sets: [], position: Int.max)])),
            \(Self.template(2, position: -5))],
            """
        let exercises = [
            Self.exercise(
                10,
                sets: [Self.set(100, position: Int.max), Self.set(101, position: 3)],
                position: Int.max,
                group: max
            ),
            Self.exercise(11, sets: [], position: -4, group: max),
            Self.exercise(12, sets: [], position: 7, group: "5"),
            Self.exercise(13, sets: [], position: 9, group: "5"),
        ]
        _ = try Importer.apply(
            try Self.document(extra: templates, workouts: [Self.workout(1, exercises: exercises)]),
            to: context
        )
        let rows = try Self.fetch(WorkoutExercise.self, in: context).sorted { $0.position < $1.position }
        #expect(rows.map(\.position) == [0, 1, 2, 3])
        // File order by position: 11 (-4), 12 (7), 13 (9), 10 (max). Groups renumbered by first appearance.
        #expect(rows.map(\.id) == [Self.id(11), Self.id(12), Self.id(13), Self.id(10)])
        #expect(rows.map(\.supersetGroup) == [1, 2, 2, 1])
        let sets = try Self.fetch(WorkoutSet.self, in: context).sorted { $0.position < $1.position }
        #expect(sets.map(\.position) == [0, 1] && sets.map(\.id) == [Self.id(101), Self.id(100)])
        let templateRows = try Self.fetch(Template.self, in: context).sorted { $0.position < $1.position }
        #expect(templateRows.map(\.position) == [0, 1] && templateRows.map(\.id) == [Self.id(2), Self.id(1)])
        #expect(try Self.fetch(TemplateExercise.self, in: context).map(\.position) == [0])
    }

    // MARK: 2. Fitness values

    private static func healthJSON(_ fields: String) -> String {
        "\"healthWorkoutId\":\"HK-1\",\(fields),"
    }

    @Test func outOfRangeFitnessValuesAreDropped() throws {
        let context = try makeTestContext()
        let health = Self.healthJSON(
            """
            "effortScore":1e300,"activeEnergyKcal":1e12,"totalEnergyKcal":-3,"avgHeartRate":5000,"maxHeartRate":150,
            "weatherTemperatureCelsius":9999,"weatherHumidityPercent":40,
            "heartRateSeries":[{"offset":600,"bpm":120},{"offset":1e12,"bpm":120},{"offset":-1e12,"bpm":120},
            {"offset":900,"bpm":1e9}],
            "heartRateZones":[{"index":1,"lowerBPM":null,"upperBPM":140,"seconds":1200},
            {"index":2,"lowerBPM":1e300,"upperBPM":null,"seconds":1e300}]
            """
        )
        _ = try Importer.apply(try Self.document(workouts: [Self.workout(1, health: health)]), to: context)
        let row = try #require(try Self.fetch(Workout.self, in: context).first)
        #expect(row.effortScore == nil)
        #expect(row.activeEnergyKcal == nil && row.totalEnergyKcal == nil)
        #expect(row.avgHeartRate == nil && row.maxHeartRate == 150)
        #expect(row.weatherTemperatureCelsius == nil && row.weatherHumidityPercent == 40)
        #expect(row.heartRateSeries == [HeartRatePoint(offset: 600, bpm: 120)])
        #expect(row.heartRateZones?.map(\.index) == [1])
    }

    @Test func inRangeFitnessValuesSurvive() throws {
        let context = try makeTestContext()
        let health = Self.healthJSON(
            """
            "effortScore":7.5,"activeEnergyKcal":450,"avgHeartRate":130,"maxHeartRate":171,
            "heartRateSeries":[{"offset":0,"bpm":90},{"offset":3600,"bpm":171}]
            """
        )
        _ = try Importer.apply(try Self.document(workouts: [Self.workout(1, health: health)]), to: context)
        let row = try #require(try Self.fetch(Workout.self, in: context).first)
        #expect(row.effortScore == 7.5 && row.activeEnergyKcal == 450 && row.avgHeartRate == 130)
        #expect(row.heartRateSeries?.count == 2)
    }

    @Test func nonFiniteFitnessValuesAreDroppedInsteadOfFailingTheImport() throws {
        var doc = try Self.document(workouts: [Self.workout(1, health: Self.healthJSON("\"effortScore\":5"))])
        doc.workouts[0].heartRateSeries = [
            HeartRatePoint(offset: 0, bpm: .nan), HeartRatePoint(offset: .infinity, bpm: 100),
        ]
        doc.workouts[0].activeEnergyKcal = .infinity
        let context = try makeTestContext()
        _ = try Importer.apply(doc, to: context)
        let row = try #require(try Self.fetch(Workout.self, in: context).first)
        #expect(row.heartRateSeriesData == nil && row.activeEnergyKcal == nil && row.effortScore == 5)
    }

    @Test func fitnessFormatNeverTrapsOnHugeOrNonFiniteNumbers() {
        #expect(FitnessFormat.wholeScore(1e300) == 10)
        #expect(FitnessFormat.wholeScore(-1e300) == 1)
        #expect(FitnessFormat.wholeScore(.nan) == 1)
        #expect(FitnessFormat.wholeScore(.infinity) == 10)
        #expect(!FitnessFormat.spokenDuration(seconds: 1e300).isEmpty)
        #expect(!FitnessFormat.spokenDuration(seconds: .nan).isEmpty)
    }

    // MARK: 3. Resumed workout

    @Test func theResumedWorkoutIsChosenAmongRowsThatWillBeApplied() throws {
        let context = try makeTestContext()
        // The store has workout 2 finished and newer than the file's copy, so the file's copy is skipped.
        _ = try Importer.apply(
            try Self.document(workouts: [
                Self.workout(2, started: "2026-01-02T10:00:00Z", updated: "2026-02-01T00:00:00Z")
            ]),
            to: context
        )
        let data = try Self.document(workouts: [
            Self.workout(1, finished: nil),
            Self.workout(2, finished: nil, started: "2026-01-02T10:00:00Z"),
        ])
        let report = try Importer.apply(data, to: context)
        let rows = try Self.fetch(Workout.self, in: context)
        let one = try #require(rows.first { $0.id == Self.id(1) })
        let two = try #require(rows.first { $0.id == Self.id(2) })
        #expect(one.finishedAt == nil, "the only applicable unfinished workout stays in progress")
        #expect(two.finishedAt != nil)
        #expect(report[.workouts].skipped == 1 && report[.workouts].inserted == 1)
    }

    // MARK: 4. Child ids under another parent

    @Test func aSetIdUnderAnotherExerciseIsNotMoved() throws {
        let context = try makeTestContext()
        let first = try Self.document(workouts: [
            Self.workout(1, exercises: [Self.exercise(10, sets: [Self.set(100)])])
        ])
        _ = try Importer.apply(first, to: context)
        // A second workout reuses exercise id 10 and set id 100.
        let second = try Self.document(workouts: [
            Self.workout(2, started: "2026-01-02T10:00:00Z", exercises: [Self.exercise(10, sets: [Self.set(100)])])
        ])
        _ = try Importer.apply(second, to: context)
        let workouts = try Self.fetch(Workout.self, in: context)
        #expect(workouts.count == 2)
        for workout in workouts {
            let exercises = try #require(workout.exercises)
            #expect(exercises.count == 1)
            #expect(exercises.first?.sets?.count == 1)
        }
        #expect(try Self.fetch(WorkoutExercise.self, in: context).count == 2)
        #expect(try Self.fetch(WorkoutSet.self, in: context).count == 2)
        // The original workout keeps its original ids.
        let original = try #require(workouts.first { $0.id == Self.id(1) })
        #expect(original.exercises?.first?.id == Self.id(10))
        #expect(original.exercises?.first?.sets?.first?.id == Self.id(100))
    }

    @Test func aSetIdRepeatedAcrossExercisesOfOneWorkoutKeepsBothSets() throws {
        let context = try makeTestContext()
        let doc = try Self.document(workouts: [
            Self.workout(
                1,
                exercises: [
                    Self.exercise(10, sets: [Self.set(100)], position: 0),
                    Self.exercise(11, sets: [Self.set(100)], position: 1),
                ]
            )
        ])
        let report = try Importer.apply(doc, to: context)
        let exercises = try Self.fetch(WorkoutExercise.self, in: context)
        #expect(exercises.count == 2 && exercises.allSatisfy { $0.sets?.count == 1 })
        #expect(report[.workoutSets].inserted == 2)
    }

    @Test func aTemplateExerciseIdUnderAnotherTemplateIsNotMoved() throws {
        let context = try makeTestContext()
        let shared = Self.exercise(20, sets: [])
        let templates = """
            "templates":[\(Self.template(1, position: 0, exercises: [shared])),
            \(Self.template(2, position: 1, exercises: [shared]))],
            """
        _ = try Importer.apply(try Self.document(extra: templates), to: context)
        let rows = try Self.fetch(Template.self, in: context)
        #expect(rows.count == 2 && rows.allSatisfy { $0.exercises?.count == 1 })
        #expect(try Self.fetch(TemplateExercise.self, in: context).count == 2)
    }

    // MARK: 5. Newer format versions

    @Test func aNewerVersionReportsUnsupportedVersionEvenWithUnknownValues() {
        let json = Self.text(
            version: 2,
            workouts: [Self.workout(1, exercises: [Self.exercise(10, sets: [Self.set(100)])])]
        ).replacingOccurrences(of: "\"kind\":\"normal\"", with: "\"kind\":\"dropset\"")
        #expect(throws: ImportError.unsupportedVersion(2)) { try WorkoutsJSON.decode(Data(json.utf8)) }
    }

    @Test func aFileWithoutAVersionIsStillDamaged() {
        #expect(throws: DecodingError.self) { try WorkoutsJSON.decode(Data("{\"workouts\":[]}".utf8)) }
        #expect(throws: DecodingError.self) { try WorkoutsJSON.decode(Data("[]".utf8)) }
    }

    // MARK: 6. Custom exercises with a library id

    @Test func aCustomExerciseWithALibraryIdIsRefused() throws {
        let libraryID = LibraryID.id(source: "smartworkout", sourceID: "100")
        let library = """
            {"version": 1, "exercises": [{"id": "\(libraryID.uuidString)", "source": "smartworkout",
             "sourceId": "100", "name": "Bench Press", "bodyPart": "chest", "weightType": "barbell"}]}
            """
        let catalog = try LibraryCatalog(data: Data(library.utf8))
        let custom = """
            "customExercises":[{"id":"\(libraryID)","name":"Hijack","aliases":[],"equipment":[],"bodyPart":"chest",
            "weightType":"barbell","instructions":[],"unit":null,"barType":"olympic","barWeight":null,
            "restSeconds":null,"retired":true,"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"},
            {"id":"\(Self.id(5))","name":"Sled","aliases":[],"equipment":[],"bodyPart":"legs","weightType":"weighted",
            "instructions":[],"unit":null,"barType":"olympic","barWeight":null,"restSeconds":null,"retired":false,
            "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}],
            """
        let context = try makeTestContext()
        let report = try Importer.apply(try Self.document(extra: custom), to: context, catalog: catalog)
        #expect(try Self.fetch(Exercise.self, in: context).map(\.id) == [Self.id(5)])
        #expect(report[.customExercises].inserted == 1 && report[.customExercises].skipped == 1)
        #expect(report.refusedCustomExercises == 1)
        #expect(report.summary.contains("reuses a library exercise"))
    }
}
