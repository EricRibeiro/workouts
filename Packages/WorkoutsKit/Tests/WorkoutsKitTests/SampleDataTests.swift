import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct SampleDataTests {
    private static let now = Date(timeIntervalSince1970: 1_793_000_000)

    private static func realCatalog() throws -> LibraryCatalog {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try LibraryCatalog(
            data: Data(contentsOf: repoRoot.appendingPathComponent("Resources/Library/library.json"))
        )
    }

    private func seeded(
        catalog: LibraryCatalog,
        now: Date = SampleDataTests.now,
        seed: UInt64 = 1
    ) throws -> ModelContext {
        let container = try makeTestContainer()
        let context = container.mainContext
        try SampleData.seed(into: context, catalog: catalog, now: now, seed: seed)
        // Keep the container alive for as long as the context is used.
        retained.append(container)
        return context
    }

    private let retained = Retained()

    private final class Retained {
        var containers: [ModelContainer] = []
        func append(_ container: ModelContainer) { containers.append(container) }
    }

    private func workouts(_ context: ModelContext) throws -> [Workout] {
        try context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startedAt)]))
    }

    @Test func insertsTheExpectedShape() throws {
        let context = try seeded(catalog: Self.realCatalog())
        let all = try workouts(context)
        #expect(all.count == 50)
        #expect(all.allSatisfy { $0.finishedAt != nil })
        #expect(all.filter { $0.finishedAt == nil }.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<TemplateFolder>()) == 2)
        let templates = try context.fetch(FetchDescriptor<Template>(sortBy: [SortDescriptor(\.position)]))
        #expect(templates.map(\.name) == ["Push", "Pull", "Legs"])
        for template in templates {
            let count = template.exercises?.count ?? 0
            #expect((4...6).contains(count))
            #expect(template.folder != nil)
        }
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<StickyNote>()) == 1)
    }

    @Test func everyOrderedChildHasAPositionAndASnapshot() throws {
        let context = try seeded(catalog: Self.realCatalog())
        for workout in try workouts(context) {
            #expect(workout.template != nil)
            let rows = (workout.exercises ?? []).sorted { $0.position < $1.position }
            #expect(rows.map(\.position) == Array(0..<rows.count))
            for row in rows {
                #expect(!row.exerciseName.isEmpty)
                let sets = (row.sets ?? []).sorted { $0.position < $1.position }
                #expect(sets.map(\.position) == Array(0..<sets.count))
                #expect(sets.allSatisfy { $0.completed })
            }
        }
        for template in try context.fetch(FetchDescriptor<Template>()) {
            let rows = (template.exercises ?? []).sorted { $0.position < $1.position }
            #expect(rows.map(\.position) == Array(0..<rows.count))
            for row in rows {
                #expect(!row.exerciseName.isEmpty)
                let sets = (row.sets ?? []).sorted { $0.position < $1.position }
                #expect(!sets.isEmpty)
                #expect(sets.map(\.position) == Array(0..<sets.count))
            }
        }
    }

    @Test func includesWarmupsAndOtherKinds() throws {
        let context = try seeded(catalog: Self.realCatalog())
        let kinds = Set(try context.fetch(FetchDescriptor<WorkoutSet>()).map(\.kind))
        #expect(kinds.contains(.warmup))
        #expect(kinds.contains(.normal))
        #expect(kinds.contains(.drop))
    }

    @Test func sameSeedIsDeterministic() throws {
        let catalog = try Self.realCatalog()
        func fingerprint(_ context: ModelContext) throws -> [String] {
            try workouts(context).map { workout in
                let sets = (workout.exercises ?? []).sorted { $0.position < $1.position }.flatMap { row in
                    (row.sets ?? []).sorted { $0.position < $1.position }.map {
                        "\(row.exerciseID)|\($0.kind.rawValue)|\($0.weight ?? -1)|\($0.reps ?? -1)"
                    }
                }
                return "\(workout.id)|\(workout.startedAt.timeIntervalSince1970)|" + sets.joined(separator: ";")
            }
        }
        let first = try fingerprint(seeded(catalog: catalog))
        let second = try fingerprint(seeded(catalog: catalog))
        #expect(first == second)
        #expect(first.count == 50)
        let other = try fingerprint(seeded(catalog: catalog, seed: 2))
        #expect(other != first)
    }

    @Test func everyWorkoutIsBeforeNowAndSpansSixMonths() throws {
        let context = try seeded(catalog: Self.realCatalog())
        let all = try workouts(context)
        for workout in all {
            let finished = try #require(workout.finishedAt)
            #expect(workout.startedAt < finished)
            #expect(finished < Self.now)
        }
        let first = try #require(all.first)
        let days = Self.now.timeIntervalSince(first.startedAt) / 86_400
        #expect(days > 120 && days < 220)
    }

    @Test func everyExerciseIDResolvesInCatalogOrCustom() throws {
        let catalog = try Self.realCatalog()
        let context = try seeded(catalog: catalog)
        let store = ExerciseStore(catalog: catalog, custom: try context.fetch(FetchDescriptor<Exercise>()))
        var ids = Set<UUID>()
        for row in try context.fetch(FetchDescriptor<WorkoutExercise>()) { ids.insert(row.exerciseID) }
        for row in try context.fetch(FetchDescriptor<TemplateExercise>()) { ids.insert(row.exerciseID) }
        for note in try context.fetch(FetchDescriptor<StickyNote>()) { ids.insert(note.exerciseID) }
        #expect(!ids.isEmpty)
        for id in ids {
            let info = try #require(store.exercise(id: id))
            #expect(!info.isRetired)
        }
        let rows = try context.fetch(FetchDescriptor<WorkoutExercise>())
        for row in rows {
            #expect(store.exercise(id: row.exerciseID)?.name == row.exerciseName)
        }
        #expect(rows.contains { store.exercise(id: $0.exerciseID)?.isCustom == true })
    }

    @Test func setsPersonalRecordsThroughThePRMath() throws {
        let catalog = try Self.realCatalog()
        let context = try seeded(catalog: catalog)
        let store = ExerciseStore(catalog: catalog, custom: try context.fetch(FetchDescriptor<Exercise>()))

        var sessions: [Session] = []
        for workout in try workouts(context) {
            for row in workout.exercises ?? [] {
                let type = try #require(store.exercise(id: row.exerciseID)).weightType
                let sets = (row.sets ?? []).map {
                    LoggedSet(kind: $0.kind, weight: $0.weight, unit: row.unit, reps: $0.reps, completed: $0.completed)
                }
                sessions.append(
                    Session(
                        workoutID: workout.id,
                        time: workout.startedAt,
                        exerciseID: row.exerciseID,
                        weightType: type,
                        sets: sets
                    )
                )
            }
        }
        var prSessions = 0
        var laterPRs = 0
        for session in sessions {
            let history = sessions.filter { $0.exerciseID == session.exerciseID }
            let prs = prsInSession(
                history: history,
                session: session,
                weightType: session.weightType,
                options: RecordsOptions()
            )
            if !prs.isEmpty {
                prSessions += 1
                if session.time > (sessions.map(\.time).min() ?? .distantPast).addingTimeInterval(86_400 * 30) {
                    laterPRs += 1
                }
            }
        }
        #expect(prSessions > 0)
        // Weights keep progressing, so PRs are not only the first session of each exercise.
        #expect(laterPRs > 10)
    }

    @Test func fallsBackWhenCatalogLacksTheNames() throws {
        let catalog = try LibraryFixture.catalog()
        let context = try seeded(catalog: catalog)
        #expect(try workouts(context).count == 50)
        let templates = try context.fetch(FetchDescriptor<Template>())
        #expect(templates.count == 3)
        for row in try context.fetch(FetchDescriptor<WorkoutExercise>()) {
            #expect(!row.exerciseName.isEmpty)
        }
    }

    @Test func previewContainerIsSeededAndInMemory() throws {
        let container = try ModelContainer.preview(catalog: Self.realCatalog())
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Workout>()) == 50)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Template>()) == 3)
    }

    @Test func randomGeneratorIsStable() {
        var a = SplitMix64(state: 1)
        var b = SplitMix64(state: 1)
        #expect((0..<10).map { _ in a.next() } == (0..<10).map { _ in b.next() })
        var zero = SplitMix64(state: 0)
        #expect(zero.next() == 0xE220_A839_7B1D_CDAF)
        var c = SplitMix64(state: 5)
        #expect((0..<100).allSatisfy { _ in (0..<7).contains(c.below(7)) })
        #expect(a.uuid() == b.uuid())
        let first = a.uuid()
        #expect(first != a.uuid())
    }

    @Test func scalesTheWorkoutCountAcrossTheRequestedSpan() throws {
        let container = try makeTestContainer()
        try SampleData.seed(
            into: container.mainContext,
            catalog: Self.realCatalog(),
            now: Self.now,
            workoutCount: 120,
            spanDays: 730
        )
        let all = try workouts(container.mainContext)
        #expect(all.count == 120)
        #expect(all.allSatisfy { $0.finishedAt != nil })
        let spanDays = Self.now.timeIntervalSince(all[0].startedAt) / 86_400
        #expect(spanDays > 700 && spanDays < 740)
        #expect(all.last.map { Self.now.timeIntervalSince($0.startedAt) < 3 * 86_400 } == true)
        withExtendedLifetime(container) {}
    }
}
