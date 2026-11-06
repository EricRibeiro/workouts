import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct CustomExerciseFormTests {
    struct Rig {
        let container: ModelContainer
        let store: ExerciseStore
        var context: ModelContext { container.mainContext }

        init() throws {
            container = try makeTestContainer()
            store = ExerciseStore(catalog: try LibraryFixture.catalog())
        }
    }

    // MARK: default bar

    @Test func defaultBarFollowsWeightType() {
        typealias Draft = CustomExerciseForm.Draft
        #expect(Draft(weightType: .barbell).barType == .olympic)
        #expect(Draft(weightType: .dumbbell).barType == BarType.none)
        #expect(Draft(weightType: .bodyweight).barType == BarType.none)
        #expect(Draft().barType == BarType.none)
        #expect(Draft(weightType: .dumbbell, barType: .ez).barType == .ez)
        #expect(Draft.defaultBarType(for: .machine) == BarType.none)
    }

    @Test func changingWeightTypeReDerivesAnUntouchedBar() {
        var draft = CustomExerciseForm.Draft(weightType: .dumbbell)
        draft.setWeightType(.barbell)
        #expect(draft.weightType == .barbell && draft.barType == .olympic)
        draft.setWeightType(.machine)
        #expect(draft.weightType == .machine && draft.barType == BarType.none)
    }

    @Test func changingWeightTypeKeepsAnExplicitBar() {
        var draft = CustomExerciseForm.Draft(weightType: .dumbbell)
        draft.barType = .ez
        draft.setWeightType(.barbell)
        #expect(draft.barType == .ez)
        draft.setWeightType(.machine)
        #expect(draft.barType == .ez)
    }

    @Test func savedDumbbellDraftHasNoBar() throws {
        let rig = try Rig()
        let created = try CustomExerciseForm.create(
            .init(name: "Curl", weightType: .dumbbell),
            in: rig.context,
            store: rig.store
        )
        #expect(created.barType == BarType.none)
        #expect(CustomExerciseForm.Draft(created).barType == BarType.none)
    }

    // MARK: validation

    @Test func nameIsRequiredAndTrimmed() throws {
        let rig = try Rig()
        #expect(CustomExerciseForm.validate(.init(name: ""), in: rig.store) == [.nameMissing])
        #expect(CustomExerciseForm.validate(.init(name: "  \n "), in: rig.store) == [.nameMissing])
        #expect(CustomExerciseForm.validate(.init(name: "  Sled Push "), in: rig.store).isEmpty)
        #expect(CustomExerciseForm.Draft(name: "  Sled Push ").trimmedName == "Sled Push")
    }

    @Test func nameLengthLimit() throws {
        let rig = try Rig()
        let ok = String(repeating: "a", count: 120)
        #expect(CustomExerciseForm.validate(.init(name: ok), in: rig.store).isEmpty)
        #expect(CustomExerciseForm.validate(.init(name: ok + "a"), in: rig.store) == [.nameTooLong])
    }

    @Test func nameMustBeUniqueAgainstLibraryAndCustom() throws {
        let rig = try Rig()
        #expect(CustomExerciseForm.validate(.init(name: "back squat"), in: rig.store) == [.nameTaken])
        #expect(CustomExerciseForm.validate(.init(name: " BACK SQUAT "), in: rig.store) == [.nameTaken])
        let created = try CustomExerciseForm.create(.init(name: "Sled Push"), in: rig.context, store: rig.store)
        #expect(CustomExerciseForm.validate(.init(name: "sled push"), in: rig.store) == [.nameTaken])
        // The exercise being edited may keep its own name.
        #expect(CustomExerciseForm.validate(.init(name: "Sled Push"), editing: created.id, in: rig.store).isEmpty)
        // Archived exercises still hold their name.
        try CustomExerciseForm.archive(created, in: rig.context, store: rig.store)
        #expect(CustomExerciseForm.validate(.init(name: "Sled Push"), in: rig.store) == [.nameTaken])
    }

    @Test func restParsing() {
        #expect(CustomExerciseForm.parseRest("90") == 90)
        #expect(CustomExerciseForm.parseRest(" 0 ") == 0)
        #expect(CustomExerciseForm.parseRest("3600") == 3600)
        #expect(CustomExerciseForm.parseRest("3601") == nil)
        #expect(CustomExerciseForm.parseRest("") == nil)
        #expect(CustomExerciseForm.parseRest("-5") == nil)
        #expect(CustomExerciseForm.parseRest("1.5") == nil)
        #expect(CustomExerciseForm.parseRest("abc") == nil)
    }

    @Test func restAndBarWeightIssues() throws {
        let rig = try Rig()
        var draft = CustomExerciseForm.Draft(name: "Sled Push", restText: "x")
        #expect(CustomExerciseForm.validate(draft, in: rig.store) == [.restInvalid])
        draft.restText = ""
        #expect(CustomExerciseForm.validate(draft, in: rig.store).isEmpty)
        draft.barType = .custom
        #expect(CustomExerciseForm.validate(draft, in: rig.store) == [.barWeightInvalid])
        draft.barWeightText = "17,5"
        #expect(CustomExerciseForm.validate(draft, in: rig.store).isEmpty)
        #expect(draft.barWeight == 17.5)
        draft.barWeightText = "1001"
        #expect(CustomExerciseForm.validate(draft, in: rig.store) == [.barWeightInvalid])
        // A stale bar weight is ignored unless the bar is custom.
        draft.barType = .ez
        #expect(CustomExerciseForm.validate(draft, in: rig.store).isEmpty)
    }

    // MARK: create / update

    @Test func createInsertsAndRefreshesStore() throws {
        let rig = try Rig()
        let draft = CustomExerciseForm.Draft(
            name: " Sled Push ",
            bodyPart: "legs",
            equipment: ["machine"],
            weightType: .machine,
            instructions: "Brace\n\n  Drive \n",
            unit: .kg,
            barType: .custom,
            barWeightText: "15",
            restText: "75"
        )
        let created = try CustomExerciseForm.create(draft, in: rig.context, store: rig.store)
        let rows = try rig.context.fetch(FetchDescriptor<Exercise>())
        #expect(rows.count == 1)
        #expect(created.name == "Sled Push")
        #expect(created.instructions == ["Brace", "Drive"])
        #expect(created.unit == .kg && created.barType == .custom && created.barWeight == 15)
        #expect(created.restSeconds == 75)
        let info = try #require(rig.store.exercise(id: created.id))
        #expect(info.isCustom && info.name == "Sled Push" && info.bodyPart == "legs")
        #expect(rig.store.search("sled").map(\.id) == [created.id])
    }

    @Test func updateRewritesFieldsAndKeepsId() throws {
        let rig = try Rig()
        let created = try CustomExerciseForm.create(
            .init(name: "Sled Push", barType: .custom, barWeightText: "15"),
            in: rig.context,
            store: rig.store
        )
        var draft = CustomExerciseForm.Draft(created)
        #expect(draft.barWeightText == "15")
        draft.name = "Sled Pull"
        draft.barType = .none
        draft.restText = "60"
        try CustomExerciseForm.update(created, from: draft, in: rig.context, store: rig.store)
        #expect(created.name == "Sled Pull" && created.barType == BarType.none)
        #expect(created.barWeight == nil && created.restSeconds == 60)
        #expect(rig.store.exercise(id: created.id)?.name == "Sled Pull")
        #expect(try rig.context.fetch(FetchDescriptor<Exercise>()).count == 1)
    }

    @Test func renameReachesTemplatesAndInProgressWorkoutButNotHistory() throws {
        let rig = try Rig()
        let created = try CustomExerciseForm.create(.init(name: "Sled Push"), in: rig.context, store: rig.store)
        let template = Template(name: "Legs")
        rig.context.insert(template)
        let planRow = TemplateExercise(exerciseID: created.id, exerciseName: "Sled Push", template: template)
        let otherRow = TemplateExercise(exerciseID: UUID(), exerciseName: "Sled Push", template: template)
        let finished = Workout(name: "Old", finishedAt: Date())
        let live = Workout(name: "Now")
        rig.context.insert(finished)
        rig.context.insert(live)
        let history = WorkoutExercise(exerciseID: created.id, exerciseName: "Sled Push", workout: finished)
        let current = WorkoutExercise(exerciseID: created.id, exerciseName: "Sled Push", workout: live)
        rig.context.insert(planRow)
        rig.context.insert(otherRow)
        rig.context.insert(history)
        rig.context.insert(current)
        var draft = CustomExerciseForm.Draft(created)
        draft.name = "Sled Pull"
        try CustomExerciseForm.update(created, from: draft, in: rig.context, store: rig.store)
        #expect(planRow.exerciseName == "Sled Pull")
        #expect(otherRow.exerciseName == "Sled Push")
        #expect(current.exerciseName == "Sled Pull")
        #expect(history.exerciseName == "Sled Push")
    }

    // MARK: references, archive, delete

    @Test func unusedExerciseIsNotReferencedAndDeletes() throws {
        let rig = try Rig()
        let created = try CustomExerciseForm.create(.init(name: "Sled Push"), in: rig.context, store: rig.store)
        let id = created.id
        rig.context.insert(StickyNote(exerciseID: id, text: "heavy"))
        try rig.context.save()
        #expect(try !CustomExerciseForm.isReferenced(exerciseID: id, in: rig.context))
        let deleted = try CustomExerciseForm.delete(created, in: rig.context, store: rig.store)
        #expect(deleted)
        #expect(rig.store.exercise(id: id) == nil)
        #expect(try rig.context.fetch(FetchDescriptor<Exercise>()).isEmpty)
        #expect(try rig.context.fetch(FetchDescriptor<StickyNote>()).isEmpty)
    }

    @Test func templateRowReferencesAndBlocksDelete() throws {
        let rig = try Rig()
        let created = try CustomExerciseForm.create(.init(name: "Sled Push"), in: rig.context, store: rig.store)
        let template = Template(name: "Legs")
        rig.context.insert(template)
        rig.context.insert(TemplateExercise(exerciseID: created.id, exerciseName: "Sled Push", template: template))
        try rig.context.save()
        #expect(try CustomExerciseForm.isReferenced(exerciseID: created.id, in: rig.context))
        let deleted = try CustomExerciseForm.delete(created, in: rig.context, store: rig.store)
        #expect(!deleted)
        #expect(rig.store.exercise(id: created.id) != nil)
    }

    @Test func workoutRowReferences() throws {
        let rig = try Rig()
        let created = try CustomExerciseForm.create(.init(name: "Sled Push"), in: rig.context, store: rig.store)
        let workout = Workout(name: "Legs")
        rig.context.insert(workout)
        rig.context.insert(WorkoutExercise(exerciseID: created.id, exerciseName: "Sled Push", workout: workout))
        try rig.context.save()
        #expect(try CustomExerciseForm.isReferenced(exerciseID: created.id, in: rig.context))
        #expect(try !CustomExerciseForm.isReferenced(exerciseID: UUID(), in: rig.context))
    }

    @Test func archiveRetiresButKeepsRowAndLookup() throws {
        let rig = try Rig()
        let created = try CustomExerciseForm.create(.init(name: "Sled Push"), in: rig.context, store: rig.store)
        try CustomExerciseForm.archive(created, in: rig.context, store: rig.store)
        #expect(created.retired)
        #expect(rig.store.exercise(id: created.id)?.isRetired == true)
        #expect(!rig.store.all().contains { $0.id == created.id })
        #expect(rig.store.all(includeRetired: true).contains { $0.id == created.id })
        #expect(try CustomExerciseForm.exercise(id: created.id, in: rig.context) === created)
    }

    @Test func failedDeleteRollsBackSoNothingIsCommittedLater() throws {
        struct SaveFailed: Error {}
        let rig = try Rig()
        let created = try CustomExerciseForm.create(.init(name: "Sled Push"), in: rig.context, store: rig.store)
        rig.context.insert(StickyNote(exerciseID: created.id, text: "heavy"))
        try rig.context.save()

        #expect(throws: SaveFailed.self) {
            try CustomExerciseForm.delete(
                created,
                in: rig.context,
                store: rig.store,
                saveHook: { throw SaveFailed() }
            )
        }
        #expect(try !rig.context.hasChanges)
        // An unrelated save afterwards must not delete the exercise or its note.
        try rig.context.save()
        #expect(try rig.context.fetch(FetchDescriptor<Exercise>()).count == 1)
        #expect(try rig.context.fetch(FetchDescriptor<StickyNote>()).count == 1)
        #expect(rig.store.exercise(id: created.id) != nil)
    }
}
