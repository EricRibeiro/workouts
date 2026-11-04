import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite @MainActor struct TemplateDraftTests {
    private let stamp = Date(timeIntervalSince1970: 1_800_000_000)

    private func container() throws -> ModelContainer {
        try ModelContainer.workouts(inMemory: true, cloudKit: false)
    }

    /// "Push": Bench (2 sets, 100 x 5, bar and rest set) and Row (1 set).
    private func template(_ context: ModelContext) -> Template {
        let template = Template(name: "Push", note: "Heavy", updatedAt: stamp)
        context.insert(template)
        for (position, spec) in [("Bench", 2), ("Row", 1)].enumerated() {
            let row = TemplateExercise(
                exerciseName: spec.0,
                position: position,
                restSeconds: 120,
                unit: .kg,
                barType: .ez,
                barWeight: 12,
                template: template,
                updatedAt: stamp
            )
            context.insert(row)
            for index in 0..<spec.1 {
                context.insert(TemplateSet(position: index, weight: 100, reps: 5, templateExercise: row))
            }
        }
        return template
    }

    private func info(_ name: String, type: WeightType = .barbell) -> ExerciseInfo {
        ExerciseInfo(id: UUID(), name: name, weightType: type, isCustom: false)
    }

    @Test func freshDraftIsCleanAndReadsTheTemplate() throws {
        let holder = try container()
        defer { withExtendedLifetime(holder) {} }
        let model = template(holder.mainContext)
        let draft = TemplateDraft(model)
        #expect(!draft.hasChanges(from: TemplateDraft(model)))
        #expect(draft.name == "Push")
        #expect(draft.note == "Heavy")
        #expect(draft.exercises.map(\.name) == ["Bench", "Row"])
        #expect(draft.exercises[0].sets.count == 2)
        #expect(draft.exercises[0].unit == .kg)
    }

    @Test func everyKindOfEditMarksTheDraftDirty() throws {
        let holder = try container()
        defer { withExtendedLifetime(holder) {} }
        let original = TemplateDraft(template(holder.mainContext))
        let setID = original.exercises[0].sets[0].id

        var weight = original
        weight.setWeight(105, for: setID)
        var count = original
        count.setCount(6, for: setID)
        var kind = original
        kind.cycleKind(of: setID)
        var added = original
        added.addSet(to: original.exercises[0].id)
        var deleted = original
        deleted.deleteSet(setID)
        var renamed = original
        renamed.rename(to: "Pull")
        var reordered = original
        reordered.reorder(original.exercises.map(\.id).reversed())
        var more = original
        more.addExercises([info("Squat")], defaultUnit: .lb, defaultRestSeconds: 90)

        for edited in [weight, count, kind, added, deleted, renamed, reordered, more] {
            #expect(edited.hasChanges(from: original))
        }
        // Changing a value back leaves it clean again.
        weight.setWeight(100, for: setID)
        #expect(!weight.hasChanges(from: original))
    }

    @Test func renameIgnoresBlankAndTrims() {
        var draft = TemplateDraft()
        #expect(draft.name == TemplateDraft.newTemplateName)
        draft.rename(to: "   ")
        #expect(draft.name == TemplateDraft.newTemplateName)
        draft.rename(to: "  Legs ")
        #expect(draft.name == "Legs")
    }

    @Test func addSetCopiesTheLastAndWarmupBecomesNormal() throws {
        let holder = try container()
        defer { withExtendedLifetime(holder) {} }
        var draft = TemplateDraft(template(holder.mainContext))
        let exercise = draft.exercises[0].id
        draft.cycleKind(of: draft.exercises[0].sets[1].id)  // normal -> warmup
        let new = UUID()
        draft.addSet(to: exercise, id: new)
        let added = draft.exercises[0].sets[2]
        #expect(added.id == new)
        #expect(added.kind == .normal)
        #expect(added.weight == 100)
        #expect(added.reps == 5)
    }

    @Test func addExercisesStartFromDefaultsAndCustomOverrides() {
        var draft = TemplateDraft()
        let custom = ExerciseInfo(
            id: UUID(),
            name: "Sled",
            weightType: .machine,
            isCustom: true,
            unit: .kg,
            barType: .none,
            restSeconds: 45
        )
        draft.addExercises(
            [info("Squat"), info("Curl", type: .dumbbell), custom],
            defaultUnit: .lb,
            defaultRestSeconds: 90
        )
        #expect(draft.exercises.map(\.name) == ["Squat", "Curl", "Sled"])
        #expect(draft.exercises.map(\.unit) == [.lb, .lb, .kg])
        #expect(draft.exercises.map(\.barType) == [.olympic, .none, .none])
        #expect(draft.exercises.map(\.restSeconds) == [90, 90, 45])
        #expect(draft.exercises.allSatisfy { $0.sets.count == TemplateDraft.defaultSetCount })
        #expect(draft.exercises.allSatisfy { $0.supersetGroup == nil })
    }

    @Test func supersetGroupsTheNewExercisesOnly() throws {
        let holder = try container()
        defer { withExtendedLifetime(holder) {} }
        var draft = TemplateDraft(template(holder.mainContext))
        let ids = draft.addExercises(
            [info("Squat"), info("Lunge")],
            defaultUnit: .lb,
            defaultRestSeconds: 90,
            asSuperset: true
        )
        #expect(draft.exercises.map(\.supersetGroup) == [nil, nil, 1, 1])
        #expect(draft.exercises.suffix(2).map(\.id) == ids)

        // A single exercise cannot form a superset.
        var single = TemplateDraft()
        single.addExercises([info("Squat")], defaultUnit: .lb, defaultRestSeconds: 90, asSuperset: true)
        #expect(single.exercises[0].supersetGroup == nil)
    }

    @Test func reorderNeedsEveryIDExactlyOnce() throws {
        let holder = try container()
        defer { withExtendedLifetime(holder) {} }
        var draft = TemplateDraft(template(holder.mainContext))
        let ids = draft.exercises.map(\.id)
        draft.reorder([ids[0]])
        draft.reorder([ids[0], ids[0]])
        #expect(draft.exercises.map(\.id) == ids)
        draft.reorder(ids.reversed())
        #expect(draft.exercises.map(\.id) == ids.reversed())
    }

    @Test func timedExercisesEditSecondsNotReps() throws {
        let holder = try container()
        defer { withExtendedLifetime(holder) {} }
        let model = template(holder.mainContext)
        model.exercises?.first { $0.exerciseName == "Row" }?.sets?.first?.durationSeconds = 30
        var draft = TemplateDraft(model)
        let row = draft.exercises[1]
        #expect(row.isTimed)
        draft.setCount(45, for: row.sets[0].id)
        #expect(draft.exercises[1].sets[0].durationSeconds == 45)
        #expect(draft.exercises[1].sets[0].reps == 5)
    }

    @Test func saveWritesValuesKeepsHiddenFieldsAndStampsOnlyChangedRows() throws {
        let holder = try container()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let model = template(context)
        var draft = TemplateDraft(model)
        draft.setWeight(105, for: draft.exercises[0].sets[0].id)
        draft.addSet(to: draft.exercises[0].id)
        draft.rename(to: "Pull")
        let now = stamp.addingTimeInterval(3600)
        try draft.save(to: model, in: context, now: now)

        #expect(model.name == "Pull")
        #expect(model.updatedAt == now)
        let rows = (model.exercises ?? []).sorted { $0.position < $1.position }
        let bench = rows[0]
        let sets = (bench.sets ?? []).sorted { $0.position < $1.position }
        #expect(sets.map(\.weight) == [105, 100, 100])
        #expect(sets.map(\.position) == [0, 1, 2])
        // Hidden fields survive.
        #expect(bench.barType == .ez)
        #expect(bench.barWeight == 12)
        #expect(bench.restSeconds == 120)
        #expect(bench.updatedAt == now)
        #expect(rows[1].updatedAt == stamp)
        // A saved draft reads back clean.
        #expect(!TemplateDraft(model).hasChanges(from: draft))
    }

    @Test func saveRemovesDeletedRowsAndSetsAndAddsNewOnes() throws {
        let holder = try container()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let model = template(context)
        var draft = TemplateDraft(model)
        draft.deleteSet(draft.exercises[0].sets[1].id)
        draft.exercises.removeAll { $0.name == "Row" }
        draft.addExercises([info("Squat")], defaultUnit: .lb, defaultRestSeconds: 90)
        try draft.save(to: model, in: context)

        let rows = (model.exercises ?? []).sorted { $0.position < $1.position }
        #expect(rows.map(\.exerciseName) == ["Bench", "Squat"])
        #expect(rows[0].sets?.count == 1)
        #expect(rows[1].sets?.count == TemplateDraft.defaultSetCount)
        #expect(rows[1].unit == .lb)
        #expect(rows[1].barType == .olympic)
        #expect(try context.fetch(FetchDescriptor<TemplateExercise>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<TemplateSet>()).count == 1 + TemplateDraft.defaultSetCount)
    }

    @Test func saveReordersAndRenumbersPositions() throws {
        let holder = try container()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let model = template(context)
        var draft = TemplateDraft(model)
        draft.reorder(draft.exercises.map(\.id).reversed())
        try draft.save(to: model, in: context)
        let rows = (model.exercises ?? []).sorted { $0.position < $1.position }
        #expect(rows.map(\.exerciseName) == ["Row", "Bench"])
    }

    @Test func insertNewCreatesTheTemplateLastInItsFolder() throws {
        let holder = try container()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let folder = TemplateFolder(name: "Strength")
        context.insert(folder)
        let existing = Template(name: "A", position: 4, folder: folder)
        context.insert(existing)

        var draft = TemplateDraft()
        draft.rename(to: "Legs")
        draft.addExercises([info("Squat")], defaultUnit: .kg, defaultRestSeconds: 60)
        let created = try draft.insertNew(in: folder, context: context, siblings: [existing], now: stamp)

        #expect(created.name == "Legs")
        #expect(created.position == 5)
        #expect(created.folder?.id == folder.id)
        #expect(created.createdAt == stamp)
        #expect(created.exercises?.count == 1)
        #expect(created.exercises?.first?.restSeconds == 60)
        #expect(try context.fetch(FetchDescriptor<Template>()).count == 2)
    }

    @Test func insertNewWithoutAFolderStartsAtZero() throws {
        let holder = try container()
        defer { withExtendedLifetime(holder) {} }
        let created = try TemplateDraft().insertNew(in: nil, context: holder.mainContext, siblings: [])
        #expect(created.position == 0)
        #expect(created.folder == nil)
        #expect(created.name == TemplateDraft.newTemplateName)
    }
}
