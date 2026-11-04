import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct FolderOperationsTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer.workouts(inMemory: true, cloudKit: false))
    }

    private func folders(_ context: ModelContext) throws -> [TemplateFolder] {
        FolderOperations.ordered(try context.fetch(FetchDescriptor<TemplateFolder>()))
    }

    private func templates(_ context: ModelContext) throws -> [Template] {
        try context.fetch(FetchDescriptor<Template>())
    }

    @Test func createAppendsAndTrims() throws {
        let context = try makeContext()
        let first = try #require(try FolderOperations.create(named: "  Push  ", in: context))
        let second = try #require(try FolderOperations.create(named: "Pull", in: context))
        #expect(first.name == "Push" && first.position == 0)
        #expect(second.position == 1)
        #expect(try folders(context).map(\.name) == ["Push", "Pull"])
    }

    @Test func createAfterGapUsesMaxPlusOne() throws {
        let context = try makeContext()
        context.insert(TemplateFolder(name: "A", position: 7))
        let new = try #require(try FolderOperations.create(named: "B", in: context))
        #expect(new.position == 8)
    }

    @Test func blankNameCreatesNothing() throws {
        let context = try makeContext()
        #expect(try FolderOperations.create(named: "   ", in: context) == nil)
        #expect(try folders(context).isEmpty)
    }

    @Test func nameIsClamped() {
        let long = String(repeating: "x", count: 300)
        #expect(FolderOperations.cleanedName(long)?.count == FolderOperations.maxNameLength)
        #expect(FolderOperations.cleanedName("\n ") == nil)
    }

    @Test func renameTrimsAndRejectsBlank() throws {
        let context = try makeContext()
        let folder = try #require(try FolderOperations.create(named: "Old", in: context))
        #expect(try FolderOperations.rename(folder, to: " New ", in: context))
        #expect(folder.name == "New")
        #expect(try !FolderOperations.rename(folder, to: "  ", in: context))
        #expect(folder.name == "New")
    }

    @Test func orderedBreaksTiesByNameThenID() {
        let a = TemplateFolder(name: "B", position: 1)
        let b = TemplateFolder(name: "A", position: 1)
        let c = TemplateFolder(name: "Z", position: 0)
        #expect(FolderOperations.ordered([a, b, c]).map(\.name) == ["Z", "A", "B"])
    }

    @Test func moveSwapsAndRenumbers() throws {
        let context = try makeContext()
        let a = TemplateFolder(name: "A", position: 0)
        let b = TemplateFolder(name: "B", position: 5)
        let c = TemplateFolder(name: "C", position: 5)
        [a, b, c].forEach(context.insert)
        try context.save()

        #expect(try FolderOperations.move(c, .up, among: [a, b, c], in: context))
        #expect(try folders(context).map(\.name) == ["A", "C", "B"])
        #expect(try folders(context).map(\.position) == [0, 1, 2])

        #expect(try FolderOperations.move(a, .down, among: [a, b, c], in: context))
        #expect(try folders(context).map(\.name) == ["C", "A", "B"])
    }

    @Test func moveAtTheEndsIsANoOp() throws {
        let context = try makeContext()
        let a = try #require(try FolderOperations.create(named: "A", in: context))
        let b = try #require(try FolderOperations.create(named: "B", in: context))
        #expect(try !FolderOperations.move(a, .up, among: [a, b], in: context))
        #expect(try !FolderOperations.move(b, .down, among: [a, b], in: context))
        #expect(!FolderOperations.canMove(a, .up, in: [a, b]))
        #expect(FolderOperations.canMove(a, .down, in: [a, b]))
        #expect(FolderOperations.canMove(b, .up, in: [a, b]))
        #expect(try folders(context).map(\.name) == ["A", "B"])
    }

    @Test func deleteMovesTemplatesToUnfiledAfterExistingOnes() throws {
        let context = try makeContext()
        let keep = TemplateFolder(name: "Keep", position: 0)
        let doomed = TemplateFolder(name: "Doomed", position: 1)
        context.insert(keep)
        context.insert(doomed)
        let loose = Template(name: "Loose", position: 4)
        context.insert(loose)
        let second = Template(name: "Second", position: 1, folder: doomed)
        let first = Template(name: "First", position: 0, folder: doomed)
        let other = Template(name: "Other", position: 0, folder: keep)
        [second, first, other].forEach(context.insert)
        try context.save()

        try FolderOperations.delete(doomed, .moveTemplatesToUnfiled, in: context)

        #expect(try folders(context).map(\.name) == ["Keep"])
        let all = try templates(context)
        #expect(all.count == 4)
        let unfiled = FolderOperations.orderedTemplates(all.filter { $0.folder == nil })
        #expect(unfiled.map(\.name) == ["Loose", "First", "Second"])
        #expect(unfiled.map(\.position) == [4, 5, 6])
        #expect(other.folder?.id == keep.id)
    }

    @Test func deleteWithTemplatesRemovesThemAndKeepsWorkouts() throws {
        let context = try makeContext()
        let doomed = TemplateFolder(name: "Doomed")
        context.insert(doomed)
        let template = Template(name: "T", folder: doomed)
        context.insert(template)
        let workout = Workout(name: "From T", template: template)
        context.insert(workout)
        let loose = Template(name: "Loose")
        context.insert(loose)
        try context.save()

        try FolderOperations.delete(doomed, .deleteTemplates, in: context)

        #expect(try folders(context).isEmpty)
        #expect(try templates(context).map(\.name) == ["Loose"])
        let survivor = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(survivor.template == nil)
    }

    @Test func deletingAnEmptyFolderWorksEitherWay() throws {
        let context = try makeContext()
        let a = try #require(try FolderOperations.create(named: "A", in: context))
        let b = try #require(try FolderOperations.create(named: "B", in: context))
        try FolderOperations.delete(a, .moveTemplatesToUnfiled, in: context)
        try FolderOperations.delete(b, .deleteTemplates, in: context)
        #expect(try folders(context).isEmpty)
    }
}
