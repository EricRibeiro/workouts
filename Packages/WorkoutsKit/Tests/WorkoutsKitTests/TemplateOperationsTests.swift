import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct TemplateOperationsTests {
    private func all(_ context: ModelContext) throws -> [Template] {
        FolderOperations.orderedTemplates(try context.fetch(FetchDescriptor<Template>()))
    }

    /// A template with two exercises (the first with two sets), every field set to something non-default.
    private func makeRich(in folder: TemplateFolder?, position: Int, context: ModelContext) -> Template {
        let template = Template(name: "Push", note: "Heavy", position: position, folder: folder)
        context.insert(template)
        let bench = TemplateExercise(
            exerciseName: "Bench Press",
            position: 0,
            supersetGroup: 1,
            note: "Pause",
            restSeconds: 120,
            unit: .kg,
            barType: .custom,
            barWeight: 15,
            template: template
        )
        context.insert(bench)
        context.insert(TemplateSet(position: 0, kind: .warmup, weight: 20, reps: 10, templateExercise: bench))
        context.insert(TemplateSet(position: 1, weight: 60, reps: 5, templateExercise: bench))
        let plank = TemplateExercise(exerciseName: "Plank", position: 1, template: template)
        context.insert(plank)
        context.insert(TemplateSet(position: 0, durationSeconds: 60, distanceMeters: 5, templateExercise: plank))
        return template
    }

    @Test func duplicateCopiesFieldsWithNewIDs() throws {
        let context = try makeTestContext()
        let folder = try #require(try FolderOperations.create(named: "Gym", in: context))
        let original = makeRich(in: folder, position: 0, context: context)
        try context.save()

        let copy = try FolderOperations.duplicate(original, in: context)

        #expect(copy.id != original.id)
        #expect(copy.name == "Push copy")
        #expect(copy.note == "Heavy")
        #expect(copy.folder?.id == folder.id)
        let rows = (copy.exercises ?? []).sorted { $0.position < $1.position }
        let sources = (original.exercises ?? []).sorted { $0.position < $1.position }
        #expect(rows.map(\.exerciseName) == ["Bench Press", "Plank"])
        let (row, source) = (rows[0], sources[0])
        #expect(row.id != source.id && row.exerciseID == source.exerciseID)
        #expect(row.supersetGroup == 1 && row.note == "Pause" && row.restSeconds == 120)
        #expect(row.unit == .kg && row.barType == .custom && row.barWeight == 15)
        let sets = (row.sets ?? []).sorted { $0.position < $1.position }
        let sourceSets = (source.sets ?? []).sorted { $0.position < $1.position }
        #expect(sets.map(\.kind) == [.warmup, .normal])
        #expect(sets.map(\.weight) == [20, 60] && sets.map(\.reps) == [10, 5])
        #expect(Set(sets.map(\.id)).isDisjoint(with: sourceSets.map(\.id)))
        let timed = try #require(rows[1].sets?.first)
        #expect(timed.durationSeconds == 60 && timed.distanceMeters == 5)
        // The original is untouched and the store holds both trees.
        #expect(original.exercises?.count == 2 && source.sets?.count == 2)
        #expect(try context.fetch(FetchDescriptor<TemplateExercise>()).count == 4)
        #expect(try context.fetch(FetchDescriptor<TemplateSet>()).count == 6)
    }

    @Test func duplicateLandsRightAfterTheOriginal() throws {
        let context = try makeTestContext()
        let folder = try #require(try FolderOperations.create(named: "Gym", in: context))
        let other = try #require(try FolderOperations.create(named: "Home", in: context))
        let a = Template(name: "A", position: 0, folder: folder)
        let b = Template(name: "B", position: 1, folder: folder)
        let c = Template(name: "C", position: 2, folder: folder)
        let elsewhere = Template(name: "Elsewhere", position: 0, folder: other)
        for template in [a, b, c, elsewhere] { context.insert(template) }
        try context.save()

        let copy = try FolderOperations.duplicate(b, in: context)

        let names = try all(context).filter { $0.folder?.id == folder.id }.map(\.name)
        #expect(names == ["A", "B", "B copy", "C"])
        #expect(copy.position == 2 && c.position == 3 && a.position == 0)
        #expect(elsewhere.position == 0)
    }

    @Test func duplicateOfAnUnfiledTemplateStaysUnfiled() throws {
        let context = try makeTestContext()
        let loose = Template(name: "Loose", position: 0)
        let tail = Template(name: "Tail", position: 1)
        context.insert(loose)
        context.insert(tail)
        try context.save()

        let copy = try FolderOperations.duplicate(loose, in: context)

        #expect(copy.folder == nil)
        #expect(try all(context).map(\.name) == ["Loose", "Loose copy", "Tail"])
    }

    @Test func moveLandsLastInTheTarget() throws {
        let context = try makeTestContext()
        let from = try #require(try FolderOperations.create(named: "From", in: context))
        let to = try #require(try FolderOperations.create(named: "To", in: context))
        let moving = Template(name: "Moving", position: 0, folder: from)
        let resident = Template(name: "Resident", position: 4, folder: to)
        context.insert(moving)
        context.insert(resident)
        try context.save()

        #expect(try FolderOperations.move(moving, to: to, in: context))

        #expect(moving.folder?.id == to.id)
        #expect(moving.position == 5)
        #expect(try all(context).filter { $0.folder?.id == to.id }.map(\.name) == ["Resident", "Moving"])
    }

    @Test func moveToNilUnfilesAfterTheUnfiledOnes() throws {
        let context = try makeTestContext()
        let folder = try #require(try FolderOperations.create(named: "Gym", in: context))
        let moving = Template(name: "Moving", position: 0, folder: folder)
        let loose = Template(name: "Loose", position: 2)
        context.insert(moving)
        context.insert(loose)
        try context.save()

        #expect(try FolderOperations.move(moving, to: nil, in: context))

        #expect(moving.folder == nil && moving.position == 3)
        #expect(try all(context).filter { $0.folder == nil }.map(\.name) == ["Loose", "Moving"])
    }

    @Test func moveToTheCurrentFolderIsANoOp() throws {
        let context = try makeTestContext()
        let folder = try #require(try FolderOperations.create(named: "Gym", in: context))
        let template = Template(name: "T", position: 3, folder: folder)
        context.insert(template)
        try context.save()

        #expect(try !FolderOperations.move(template, to: folder, in: context))
        #expect(template.position == 3)
    }

    @Test func deleteRemovesTheTreeAndKeepsWorkouts() throws {
        let context = try makeTestContext()
        let template = makeRich(in: nil, position: 0, context: context)
        let keep = Template(name: "Keep", position: 1)
        context.insert(keep)
        context.insert(Workout(name: "From Push", template: template))
        try context.save()

        try FolderOperations.delete(template, in: context)

        #expect(try all(context).map(\.name) == ["Keep"])
        #expect(try context.fetch(FetchDescriptor<TemplateExercise>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TemplateSet>()).isEmpty)
        let survivor = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(survivor.template == nil)
    }
}
