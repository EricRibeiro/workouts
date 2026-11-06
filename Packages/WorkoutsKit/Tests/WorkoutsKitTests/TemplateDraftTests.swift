import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite @MainActor struct TemplateDraftTests {
    private let stamp = TestSupport.referenceDate

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
        let holder = try makeTestContainer()
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

    @Test func templateNoteTrimsClearsAndSaves() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let model = template(context)
        let original = TemplateDraft(model)
        var draft = original
        draft.setNote("  Chest day.\n ")
        #expect(draft.note == "Chest day.")
        #expect(draft.hasChanges(from: original))
        try draft.save(to: model, in: context)
        #expect(model.note == "Chest day.")
        draft.setNote("   ")
        #expect(draft.note.isEmpty)
        try draft.save(to: model, in: context)
        #expect(model.note.isEmpty)
    }

    @Test func everyKindOfEditMarksTheDraftDirty() throws {
        let holder = try makeTestContainer()
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
        more.addExercises([info("Squat")], defaultUnit: .lb)

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
        let holder = try makeTestContainer()
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
            defaultUnit: .lb
        )
        #expect(draft.exercises.map(\.name) == ["Squat", "Curl", "Sled"])
        #expect(draft.exercises.map(\.unit) == [.lb, .lb, .kg])
        #expect(draft.exercises.map(\.barType) == [.olympic, .none, .none])
        #expect(draft.exercises.map(\.restSeconds) == [nil, nil, 45])
        #expect(draft.exercises.allSatisfy { $0.sets.count == TemplateDraft.defaultSetCount })
        #expect(draft.exercises.allSatisfy { $0.supersetGroup == nil })
    }

    @Test func newRowsKeepRestNilAndOffStaysZero() {
        var draft = TemplateDraft()
        let ids = draft.addExercises([info("Squat"), info("Curl", type: .dumbbell)], defaultUnit: .lb)
        #expect(draft.exercises.map(\.restSeconds) == [nil, nil])
        draft.updateRestTimers(0, for: ids[0])
        #expect(draft.exercises.map(\.restSeconds) == [0, nil])
        draft.replaceExercise(ids[0], with: info("Deadlift"), defaultUnit: .lb)
        #expect(draft.exercises[0].restSeconds == nil)
    }

    @Test func reorderingAMemberAwayFromItsPartnerLeavesTheSuperset() {
        var draft = TemplateDraft()
        let ids = draft.addExercises(
            [info("A"), info("B"), info("C"), info("D")],
            defaultUnit: .kg
        )
        draft.makeSuperset([ids[0], ids[1]])
        draft.reorder([ids[0], ids[2], ids[1], ids[3]])
        #expect(draft.exercises.map(\.id) == [ids[0], ids[2], ids[1], ids[3]])
        #expect(draft.exercises.map(\.supersetGroup) == [nil, nil, nil, nil])
        // A reorder that keeps the pair together keeps the superset.
        draft.makeSuperset([ids[0], ids[1]])
        draft.reorder([ids[3], ids[2], ids[1], ids[0]])
        #expect(draft.exercises.map(\.supersetGroup) == [nil, nil, 1, 1])
    }

    @Test func supersetGroupsTheNewExercisesOnly() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        var draft = TemplateDraft(template(holder.mainContext))
        let ids = draft.addExercises(
            [info("Squat"), info("Lunge")],
            defaultUnit: .lb,
            asSuperset: true
        )
        #expect(draft.exercises.map(\.supersetGroup) == [nil, nil, 1, 1])
        #expect(draft.exercises.suffix(2).map(\.id) == ids)

        // A single exercise cannot form a superset.
        var single = TemplateDraft()
        single.addExercises([info("Squat")], defaultUnit: .lb, asSuperset: true)
        #expect(single.exercises[0].supersetGroup == nil)
    }

    @Test func reorderNeedsEveryIDExactlyOnce() throws {
        let holder = try makeTestContainer()
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
        let holder = try makeTestContainer()
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
        let holder = try makeTestContainer()
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
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let model = template(context)
        var draft = TemplateDraft(model)
        draft.deleteSet(draft.exercises[0].sets[1].id)
        draft.exercises.removeAll { $0.name == "Row" }
        draft.addExercises([info("Squat")], defaultUnit: .lb)
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
        let holder = try makeTestContainer()
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
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let context = holder.mainContext
        let folder = TemplateFolder(name: "Strength")
        context.insert(folder)
        let existing = Template(name: "A", position: 4, folder: folder)
        context.insert(existing)

        var draft = TemplateDraft()
        draft.rename(to: "Legs")
        draft.addExercises([info("Squat")], defaultUnit: .kg)
        let created = try draft.insertNew(in: folder, context: context, siblings: [existing], now: stamp)

        #expect(created.name == "Legs")
        #expect(created.position == 5)
        #expect(created.folder?.id == folder.id)
        #expect(created.createdAt == stamp)
        #expect(created.exercises?.count == 1)
        #expect(created.exercises?.first?.restSeconds == nil)
        #expect(try context.fetch(FetchDescriptor<Template>()).count == 2)
    }

    @Test func insertNewWithoutAFolderStartsAtZero() throws {
        let holder = try makeTestContainer()
        defer { withExtendedLifetime(holder) {} }
        let created = try TemplateDraft().insertNew(in: nil, context: holder.mainContext, siblings: [])
        #expect(created.position == 0)
        #expect(created.folder == nil)
        #expect(created.name == TemplateDraft.newTemplateName)
    }

    // MARK: Block actions (3.6)

    /// A draft of blocks named `names`, each with three empty sets, ids returned in order.
    private func blocks(_ names: [String]) -> (draft: TemplateDraft, ids: [UUID]) {
        var draft = TemplateDraft()
        let ids = draft.addExercises(names.map { info($0) }, defaultUnit: .lb)
        return (draft, ids)
    }

    private func groups(_ draft: TemplateDraft) -> [Int?] { draft.exercises.map(\.supersetGroup) }

    @Test func setNoteTrimsAndClears() {
        var (draft, ids) = blocks(["Squat", "Row"])
        draft.setNote("  Pause at the bottom \n", for: ids[0])
        #expect(draft.exercises[0].note == "Pause at the bottom")
        #expect(draft.exercises[1].note == "")
        draft.setNote("   ", for: ids[0])
        #expect(draft.exercises[0].note == "")
    }

    @Test func addWarmupSetsInsertsTheRampBeforeTheWorkingSets() {
        var (draft, ids) = blocks(["Squat"])
        for set in draft.exercises[0].sets { draft.setWeight(200, for: set.id) }
        let working = draft.exercises[0].sets.map(\.id)

        // 200 lb on the Olympic bar: bar x 10, 80 x 8, 120 x 5, 160 x 3.
        #expect(draft.addWarmupSets(to: ids[0]) == 4)
        let sets = draft.exercises[0].sets
        #expect(sets.map(\.kind) == [.warmup, .warmup, .warmup, .warmup, .normal, .normal, .normal])
        #expect(sets.prefix(4).map(\.weight) == [45, 80, 120, 160])
        #expect(sets.prefix(4).map(\.reps) == [10, 8, 5, 3])
        #expect(sets.suffix(3).map(\.id) == working)
    }

    @Test func addWarmupSetsReplacesEarlierWarmupsAndUsesTheBlocksBar() {
        var (draft, ids) = blocks(["Squat"])
        draft.setUnit(.kg, for: ids[0])
        draft.setBar(.none, weight: nil, for: ids[0])
        for set in draft.exercises[0].sets { draft.setWeight(100, for: set.id) }
        draft.addWarmupSets(to: ids[0])
        let first = draft.exercises[0].sets.filter { $0.kind == .warmup }
        #expect(first.map(\.weight) == [40, 60, 80])  // no bar step; 2.5 kg plates

        draft.addWarmupSets(to: ids[0])
        let again = draft.exercises[0].sets
        #expect(again.filter { $0.kind == .warmup }.count == 3)
        #expect(again.count == 6)
        #expect(Set(again.map(\.id)).isDisjoint(with: first.map(\.id)))
    }

    @Test func addWarmupSetsWithoutAWeightDoesNothing() {
        var (draft, ids) = blocks(["Squat"])
        let before = draft
        #expect(draft.addWarmupSets(to: ids[0]) == 0)
        #expect(draft == before)
        // A warm-up set's own weight is not a working weight.
        draft.cycleKind(of: draft.exercises[0].sets[0].id)
        draft.setWeight(100, for: draft.exercises[0].sets[0].id)
        let withWarmupOnly = draft
        draft.addWarmupSets(to: ids[0])
        #expect(draft == withWarmupOnly)
    }

    @Test func updateRestTimersSetsOnlyThatBlock() {
        var (draft, ids) = blocks(["A", "B"])
        draft.makeSuperset(ids)
        draft.updateRestTimers(45, for: ids[0])
        #expect(draft.exercises.map(\.restSeconds) == [45, nil])
        draft.updateRestTimers(0, for: ids[0])
        #expect(draft.exercises[0].restSeconds == 0)
        draft.updateRestTimers(nil, for: ids[0])
        #expect(draft.exercises[0].restSeconds == nil)
    }

    @Test func changingTheUnitConvertsACustomBarOnly() {
        var (draft, ids) = blocks(["Squat", "Row"])
        draft.setUnit(.kg, for: ids[1])
        draft.setBar(.custom, weight: 20, for: ids[1])
        draft.setUnit(.lb, for: ids[1])
        #expect(draft.exercises[1].unit == .lb)
        #expect(draft.exercises[1].barWeight == round05(convert(20, from: .kg, to: .lb)))  // 44
        draft.setUnit(.lb, for: ids[1])  // same unit: untouched
        #expect(draft.exercises[1].barWeight == 44)
        draft.setUnit(.kg, for: ids[1])
        #expect(draft.exercises[1].barWeight == 20)
        // A named bar has no custom weight to convert.
        draft.setBar(.ez, weight: nil, for: ids[1])
        draft.setUnit(.lb, for: ids[1])
        #expect(draft.exercises[1].barWeight == nil)
    }

    @Test func unitAndBarPreferencesApplyToTheBlock() {
        var (draft, ids) = blocks(["Squat", "Row"])
        draft.setUnit(.kg, for: ids[1])
        draft.setBar(.custom, weight: 15, for: ids[1])
        #expect(draft.exercises.map(\.unit) == [.lb, .kg])
        #expect(draft.exercises.map(\.barType) == [.olympic, .custom])
        #expect(draft.exercises.map(\.barWeight) == [nil, 15])
        draft.setBar(.ez, weight: nil, for: ids[1])
        #expect(draft.exercises[1].barType == .ez)
        #expect(draft.exercises[1].barWeight == nil)
    }

    @Test func replaceExerciseSwapsTheExerciseAndKeepsSetsNoteAndPosition() {
        var (draft, ids) = blocks(["Squat", "Row"])
        draft.setNote("Slow", for: ids[0])
        draft.setWeight(100, for: draft.exercises[0].sets[0].id)
        let setIDs = draft.exercises[0].sets.map(\.id)
        let custom = ExerciseInfo(
            id: UUID(),
            name: "Sled",
            weightType: .machine,
            isCustom: true,
            unit: .kg,
            barType: BarType.none,
            restSeconds: 45
        )

        draft.replaceExercise(ids[0], with: custom, defaultUnit: .lb)
        let block = draft.exercises[0]
        #expect(block.id == ids[0])
        #expect(block.exerciseID == custom.id)
        #expect(block.name == "Sled")
        #expect(block.unit == .kg)
        #expect(block.barType == BarType.none)
        #expect(block.restSeconds == 45)
        #expect(block.note == "Slow")
        #expect(block.sets.map(\.id) == setIDs)
        #expect(block.sets[0].weight == 100)
        #expect(draft.exercises[1].name == "Row")

        // A library barbell takes the defaults.
        draft.replaceExercise(ids[0], with: info("Deadlift"), defaultUnit: .lb)
        #expect(draft.exercises[0].unit == .lb)
        #expect(draft.exercises[0].barType == .olympic)
        #expect(draft.exercises[0].restSeconds == nil)
    }

    @Test func replaceExerciseInsideASupersetKeepsTheGroup() {
        var (draft, ids) = blocks(["A", "B", "C"])
        draft.makeSuperset([ids[0], ids[1]])
        draft.replaceExercise(ids[1], with: info("Curl", type: .dumbbell), defaultUnit: .kg)
        #expect(groups(draft) == [1, 1, nil])
        #expect(draft.exercises.map(\.name) == ["A", "Curl", "C"])
    }

    @Test func makeSupersetGathersMembersAtTheFirstOnesPosition() {
        var (draft, ids) = blocks(["A", "B", "C", "D"])
        draft.makeSuperset([ids[3], ids[0]])
        #expect(draft.exercises.map(\.name) == ["A", "D", "B", "C"])
        #expect(groups(draft) == [1, 1, nil, nil])

        // A second group numbers after the first; a one-member request changes nothing.
        draft.makeSuperset([ids[2], ids[1]])
        #expect(groups(draft) == [1, 1, 2, 2])
        let before = draft
        draft.makeSuperset([ids[0]])
        #expect(draft == before)
    }

    @Test func makeSupersetDissolvesAGroupItShrinks() {
        var (draft, ids) = blocks(["A", "B", "C"])
        draft.makeSuperset([ids[0], ids[1]])
        draft.makeSuperset([ids[1], ids[2]])
        #expect(draft.exercises.map(\.name) == ["A", "B", "C"])
        #expect(groups(draft) == [nil, 1, 1])
    }

    @Test func removeFromSupersetDissolvesAPairAndRenumbersTheRest() {
        var (draft, ids) = blocks(["A", "B", "C", "D", "E"])
        draft.makeSuperset([ids[0], ids[1]])
        draft.makeSuperset([ids[2], ids[3], ids[4]])
        #expect(groups(draft) == [1, 1, 2, 2, 2])

        draft.removeFromSuperset(ids[3])
        #expect(groups(draft) == [1, 1, 2, nil, 2])
        draft.removeFromSuperset(ids[0])
        #expect(groups(draft) == [nil, nil, 1, nil, 1])
        #expect(draft.exercises.map(\.name) == ["A", "B", "C", "D", "E"])
        // Not in a superset: untouched.
        let before = draft
        draft.removeFromSuperset(ids[3])
        #expect(draft == before)
    }

    @Test func removeExerciseLeavingOneMemberDissolvesTheGroup() {
        var (draft, ids) = blocks(["A", "B", "C", "D"])
        draft.makeSuperset([ids[0], ids[1]])
        draft.makeSuperset([ids[2], ids[3]])
        draft.removeExercise(ids[0])
        #expect(draft.exercises.map(\.name) == ["B", "C", "D"])
        #expect(groups(draft) == [nil, 1, 1])
    }

    @Test func removeExerciseDropsTheBlockWithItsSets() {
        var (draft, ids) = blocks(["A", "B"])
        draft.removeExercise(ids[1])
        #expect(draft.exercises.map(\.id) == [ids[0]])
    }

    @Test func blockActionsOnAnUnknownIdAreNoOps() {
        var (draft, ids) = blocks(["A", "B"])
        draft.makeSuperset(ids)
        for set in draft.exercises[0].sets { draft.setWeight(100, for: set.id) }
        let before = draft
        let ghost = UUID()

        draft.setNote("x", for: ghost)
        #expect(draft.addWarmupSets(to: ghost) == 0)
        draft.updateRestTimers(30, for: ghost)
        draft.setUnit(.kg, for: ghost)
        draft.setBar(.ez, weight: 10, for: ghost)
        draft.replaceExercise(ghost, with: info("X"), defaultUnit: .kg)
        draft.removeFromSuperset(ghost)
        draft.removeExercise(ghost)
        #expect(draft == before)
        draft.makeSuperset([ghost, ids[0]])
        #expect(draft == before)
    }
}
