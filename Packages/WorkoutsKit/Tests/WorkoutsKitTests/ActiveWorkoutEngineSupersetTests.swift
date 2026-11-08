import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct EngineSupersetWarmupTests {
    private func rows(_ workout: Workout) -> [WorkoutExercise] {
        (workout.exercises ?? []).sorted { $0.position < $1.position }
    }

    private func sets(_ row: WorkoutExercise) -> [WorkoutSet] {
        (row.sets ?? []).sorted { $0.position < $1.position }
    }

    /// Three rows (squat, curl, stretch) in a fresh empty workout.
    private func threeRows() throws -> (EngineTests.Rig, ActiveWorkoutEngine, [WorkoutExercise]) {
        let rig = try EngineTests.Rig()
        let engine = try rig.makeEngine()
        try engine.startEmpty()
        let a = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let b = try engine.addExercise(try rig.info(LibraryFixture.curl))
        let c = try engine.addExercise(try rig.info(LibraryFixture.etirement))
        return (rig, engine, [a, b, c])
    }

    // MARK: - makeSuperset

    @Test func makeSupersetGathersMembersAtTheFirstOne() throws {
        let (rig, engine, rows3) = try threeRows()
        let (a, b, c) = (rows3[0], rows3[1], rows3[2])
        rig.clock.advance(60)
        try engine.makeSuperset([c, a])
        let workout = try #require(engine.workout)
        #expect(rows(workout).map(\.id) == [a.id, c.id, b.id])
        #expect(rows(workout).map(\.position) == [0, 1, 2])
        #expect(rows(workout).map(\.supersetGroup) == [1, 1, nil])
        #expect(workout.updatedAt == rig.clock.date)
        #expect([a, b, c].allSatisfy { $0.updatedAt == rig.clock.date })
        // A row that neither moved nor changed group keeps its stamp.
        rig.clock.advance(60)
        try engine.makeSuperset([a, c])
        #expect(a.updatedAt != rig.clock.date && c.updatedAt != rig.clock.date && b.updatedAt != rig.clock.date)
        #expect(try #require(engine.workout).updatedAt == rig.clock.date)
    }

    @Test func makeSupersetPersistsAcrossRelaunch() throws {
        let (rig, engine, rows3) = try threeRows()
        try engine.makeSuperset([rows3[0], rows3[2]])
        let resumed = try #require(try rig.makeEngine().workout)
        #expect(rows(resumed).map(\.id) == [rows3[0].id, rows3[2].id, rows3[1].id])
        #expect(rows(resumed).map(\.supersetGroup) == [1, 1, nil])
    }

    @Test func editingASupersetDissolvesWhatItLeavesAlone() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let (a, b, c) = (rows3[0], rows3[1], rows3[2])
        try engine.makeSuperset([a, b, c])
        #expect(rows(try #require(engine.workout)).map(\.supersetGroup) == [1, 1, 1])
        try engine.makeSuperset([a, b])
        #expect([a, b, c].map(\.supersetGroup) == [1, 1, nil])
        try engine.makeSuperset([b, c])
        #expect(rows(try #require(engine.workout)).map(\.id) == [a.id, b.id, c.id])
        #expect([a, b, c].map(\.supersetGroup) == [nil, 1, 1])
    }

    @Test func makeSupersetWithOneRowChangesNothing() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        try engine.makeSuperset([rows3[1]])
        #expect(rows3.map(\.supersetGroup) == [nil, nil, nil])
        #expect(rows3.map(\.position) == [0, 1, 2])
    }

    @Test func makeSupersetRefusesAForeignRowAndChangesNothing() throws {
        let (rig, engine, rows3) = try threeRows()
        let stranger = WorkoutExercise(exerciseID: LibraryFixture.squat)
        rig.context.insert(stranger)
        #expect(throws: ActiveWorkoutError.notInActiveWorkout) { try engine.makeSuperset([rows3[0], stranger]) }
        #expect(rows3.map(\.supersetGroup) == [nil, nil, nil])
        try engine.discard()
        #expect(throws: ActiveWorkoutError.noActiveWorkout) { try engine.makeSuperset(rows3) }
    }

    // MARK: - addWarmupSets

    private func setUpWorkingSets(_ engine: ActiveWorkoutEngine, _ row: WorkoutExercise, weight: Double?) throws {
        for set in sets(row) { try engine.setValues(set, weight: weight, reps: 5, durationSeconds: nil) }
    }

    @Test func addWarmupSetsPutsTheRampAheadOfTheWorkingSets() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let squat = rows3[0]
        try setUpWorkingSets(engine, squat, weight: 100)
        let working = sets(squat).map(\.id)
        try engine.addWarmupSets(to: squat)
        let all = sets(squat)
        #expect(all.map(\.kind) == [.warmup, .warmup, .warmup, .normal, .normal, .normal])
        #expect(all.map(\.weight) == [45, 60, 80, 100, 100, 100])
        #expect(all.prefix(3).map(\.reps) == [10, 5, 3])
        #expect(all.map(\.position) == [0, 1, 2, 3, 4, 5])
        #expect(all.suffix(3).map(\.id) == working)
        #expect(all.allSatisfy { !$0.completed })
    }

    @Test func addWarmupSetsReplacesExistingWarmups() throws {
        let (rig, engine, rows3) = try threeRows()
        let squat = rows3[0]
        try setUpWorkingSets(engine, squat, weight: 200)
        let first = sets(squat)[0]
        try engine.setKind(first, to: .warmup)
        try engine.setValues(first, weight: 20, reps: 15, durationSeconds: nil)
        try engine.addWarmupSets(to: squat)
        try engine.addWarmupSets(to: squat)
        let all = sets(squat)
        // The old warm-up is gone, the ramp is 45/80/120/160, then the two remaining working sets; the set that
        // was demoted to a warm-up held 20 lb, so the first working set is the next one (200 lb).
        #expect(all.map(\.kind) == [.warmup, .warmup, .warmup, .warmup, .normal, .normal])
        #expect(all.map(\.weight) == [45, 80, 120, 160, 200, 200])
        #expect(all.map(\.position) == [0, 1, 2, 3, 4, 5])
        #expect(!all.contains { $0.id == first.id })
        // 6 squat sets (4 ramp + 2 working) plus the 3 + 3 of the other rows: nothing leaked.
        #expect(try rig.context.fetchCount(FetchDescriptor<WorkoutSet>()) == 12)
    }

    @Test func addWarmupSetsKeepsCompletedWarmupsAndReplacesOnlyTheRest() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let squat = rows3[0]
        try setUpWorkingSets(engine, squat, weight: 100)
        let done = Array(sets(squat).prefix(2))
        for set in done {
            try engine.setKind(set, to: .warmup)
            try engine.setValues(set, weight: 20, reps: 15, durationSeconds: nil)
            try engine.check(set)
        }
        let working = try #require(sets(squat).last)
        // An unchecked warm-up added by hand is replaced like before.
        let extra = try engine.addSet(to: squat)
        try engine.setKind(extra, to: .warmup)
        try engine.addWarmupSets(to: squat)
        let all = sets(squat)
        #expect(all.map(\.kind) == [.warmup, .warmup, .warmup, .warmup, .warmup, .normal])
        #expect(all.prefix(2).map(\.id) == done.map(\.id))
        #expect(all.prefix(2).allSatisfy { $0.completed && $0.completedAt != nil && $0.weight == 20 && $0.reps == 15 })
        #expect(all.map(\.weight) == [20, 20, 45, 60, 80, 100])
        #expect(all.map(\.position) == [0, 1, 2, 3, 4, 5])
        #expect(all.suffix(3).allSatisfy { !$0.completed })
        #expect(all.last?.id == working.id)
        #expect(!all.contains { $0.id == extra.id })
        // Plan and Previous still match by kind: the working set is the first non-warm-up.
        #expect(engine.canCheck(working))
    }

    @Test func addWarmupSetsKeepsThePlanAndPreviousOnTheWorkingSets() throws {
        let rig = try EngineTests.Rig()
        rig.settings.defaultUnit = .kg
        rig.finishedWorkout(
            exercise: LibraryFixture.squat,
            unit: .kg,
            sets: [(40, 10, .warmup), (100, 5, .normal), (105, 4, .normal)],
            startedAt: rig.clock.date.addingTimeInterval(-86_400)
        )
        let engine = try rig.makeEngine()
        let workout = try engine.start(from: try rig.pushTemplate())
        let squat = try #require((workout.exercises ?? []).first { $0.exerciseID == LibraryFixture.squat })
        // Template: warm-up 60 x 5, then two working sets of 100 x 5. Previous: warm-up 40 x 10, 100 x 5, 105 x 4.
        let working = Array(sets(squat).suffix(2))
        try engine.setValues(working[0], weight: 100, reps: nil, durationSeconds: nil)
        try engine.addWarmupSets(to: squat)
        let all = sets(squat)
        let warmups = all.filter { $0.kind == .warmup }
        #expect(warmups.count > 2)
        // Working sets keep their own plan and Previous and stay checkable.
        #expect(working.map { engine.plan(for: $0) } == [SetPlan(weight: 100, reps: 5), SetPlan(weight: 100, reps: 5)])
        #expect(engine.previous(for: working[0]) == PreviousSet(kind: .normal, weight: 100, reps: 5))
        #expect(engine.previous(for: working[1]) == PreviousSet(kind: .normal, weight: 105, reps: 4))
        #expect(working.allSatisfy { engine.canCheck($0) })
        // The first warm-up takes the one planned and previous warm-up; the rest have none.
        #expect(engine.plan(for: warmups[0]) == SetPlan(weight: 60, reps: 5))
        #expect(engine.previous(for: warmups[0]) == PreviousSet(kind: .warmup, weight: 40, reps: 10))
        #expect(warmups.dropFirst().allSatisfy { engine.plan(for: $0) == nil && engine.previous(for: $0) == nil })
    }

    // MARK: - reorderExercises and supersets

    @Test func reorderingAMemberAwayFromItsPartnerLeavesTheSuperset() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let (a, b, c) = (rows3[0], rows3[1], rows3[2])
        try engine.makeSuperset([a, b])
        try engine.reorderExercises([a, c, b])
        let workout = try #require(engine.workout)
        #expect(rows(workout).map(\.id) == [a.id, c.id, b.id])
        #expect(rows(workout).map(\.supersetGroup) == [nil, nil, nil])
    }

    @Test func droppingAnExerciseInsideASupersetParksItAfterTheSuperset() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let (a, b, c) = (rows3[0], rows3[1], rows3[2])
        let d = try engine.addExercise(try rig.info(LibraryFixture.squat))
        try engine.makeSuperset([a, b, d])
        // c dragged between a and b: the superset stays whole and c is placed after it.
        try engine.reorderExercises([a, c, b, d], moving: [c])
        let workout = try #require(engine.workout)
        #expect(rows(workout).map(\.id) == [a.id, b.id, d.id, c.id])
        #expect(rows(workout).map(\.supersetGroup) == [1, 1, 1, nil])
    }

    @Test func reorderingOneOfThreeKeepsTheRestAndRenumbers() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let (a, b, c) = (rows3[0], rows3[1], rows3[2])
        let d = try engine.addExercise(try rig.info(LibraryFixture.squat))
        try engine.makeSuperset([a, b, c])
        try engine.reorderExercises([a, b, d, c])
        #expect(rows(try #require(engine.workout)).map(\.id) == [a.id, b.id, d.id, c.id])
        #expect(rows(try #require(engine.workout)).map(\.supersetGroup) == [1, 1, nil, nil])
        // Reordering that keeps the group together leaves it.
        try engine.reorderExercises([d, b, a, c])
        #expect(rows(try #require(engine.workout)).map(\.supersetGroup) == [nil, 1, 1, nil])
    }

    @Test func addWarmupSetsUsesTheRowsUnitAndBar() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let squat = rows3[0]
        squat.unit = .kg
        squat.barType = .custom
        squat.barWeight = 10
        try setUpWorkingSets(engine, squat, weight: 100)
        try engine.addWarmupSets(to: squat)
        #expect(sets(squat).filter { $0.kind == .warmup }.map(\.weight) == [10, 40, 60, 80])
        squat.barType = .none
        try engine.addWarmupSets(to: squat)
        #expect(sets(squat).filter { $0.kind == .warmup }.map(\.weight) == [40, 60, 80])
    }

    @Test func addWarmupSetsWithoutAWorkingWeightChangesNothing() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let squat = rows3[0]
        let before = sets(squat).map(\.id)
        try engine.addWarmupSets(to: squat)
        #expect(sets(squat).map(\.id) == before)
        #expect(sets(squat).allSatisfy { $0.kind == .normal })
    }

    @Test func anEmptyRampStillClearsOldWarmups() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let squat = rows3[0]
        try setUpWorkingSets(engine, squat, weight: 100)
        try engine.addWarmupSets(to: squat)
        for set in sets(squat) where set.kind == .normal {
            try engine.setValues(set, weight: 45, reps: 5, durationSeconds: nil)
        }
        try engine.addWarmupSets(to: squat)
        #expect(sets(squat).map(\.kind) == [.normal, .normal, .normal])
        #expect(sets(squat).map(\.position) == [0, 1, 2])
    }

    @Test func addWarmupSetsRefusesAForeignRow() throws {
        let (rig, engine, _) = try threeRows()
        let stranger = WorkoutExercise(exerciseID: LibraryFixture.squat)
        rig.context.insert(stranger)
        #expect(throws: ActiveWorkoutError.notInActiveWorkout) { try engine.addWarmupSets(to: stranger) }
    }

    @Test func addWarmupSetsReportsWhetherItApplied() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let squat = rows3[0]
        #expect(try engine.addWarmupSets(to: squat) == false)
        try setUpWorkingSets(engine, squat, weight: 100)
        #expect(try engine.addWarmupSets(to: squat) == true)
    }

    // MARK: - Block edits (3.6d)

    @Test func removeFromSupersetDissolvesAPairAndRenumbers() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        try engine.makeSuperset([rows3[0], rows3[1]])
        try engine.removeFromSuperset(rows3[1])
        #expect(rows3.map(\.supersetGroup) == [nil, nil, nil])
    }

    @Test func removeFromSupersetKeepsTheRestOfABiggerGroupAndRenumbers() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        try engine.makeSuperset([rows3[0], rows3[1], rows3[2]])
        try engine.removeFromSuperset(rows3[0])
        #expect(rows3.map(\.supersetGroup) == [nil, 1, 1])
    }

    /// Removing the first, middle or last member of a 3-member superset (group 1) that is followed by a pair (group 2):
    /// the group stays contiguous, the removed row sits right after it, and the pair renumbers behind it.
    @Test(arguments: [0, 1, 2])
    func removeFromSupersetKeepsTheTripleContiguous(removed: Int) throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let d = try engine.addExercise(try rig.info(LibraryFixture.squat))
        let e = try engine.addExercise(try rig.info(LibraryFixture.curl))
        try engine.makeSuperset(rows3)
        try engine.makeSuperset([d, e])
        #expect(rows3.map(\.supersetGroup) == [1, 1, 1] && [d, e].map(\.supersetGroup) == [2, 2])

        let target = rows3[removed]
        try engine.removeFromSuperset(target)

        let ordered = rows(try #require(engine.workout))
        let members = rows3.filter { $0.id != target.id }
        // The first member is already ahead of what is left of the group, so it stays; the others sit right after it.
        let expectedOrder = removed == 0 ? [target] + members : members + [target]
        #expect(ordered.map(\.id) == (expectedOrder + [d, e]).map(\.id))
        #expect(ordered.map(\.position) == [0, 1, 2, 3, 4])
        #expect(ordered.map(\.supersetGroup) == (removed == 0 ? [nil, 1, 1, 2, 2] : [1, 1, nil, 2, 2]))
    }

    @Test func removeFromSupersetOutsideAGroupChangesNothing() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        try engine.removeFromSuperset(rows3[2])
        #expect(rows3.map(\.supersetGroup) == [nil, nil, nil])
        #expect(rows3.map(\.position) == [0, 1, 2])
    }

    @Test func failedRemoveFromSupersetRollsBack() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        try engine.makeSuperset([rows3[0], rows3[1]])
        engine.saveHook = { throw BlockEditSaveFailed() }
        #expect(throws: BlockEditSaveFailed.self) { try engine.removeFromSuperset(rows3[0]) }
        #expect(rows3[0].supersetGroup == 1 && rows3[1].supersetGroup == 1)
    }

    @Test func blockEditsRefuseAForeignRow() throws {
        let (rig, engine, _) = try threeRows()
        let stranger = WorkoutExercise(exerciseID: LibraryFixture.squat)
        rig.context.insert(stranger)
        #expect(throws: ActiveWorkoutError.notInActiveWorkout) { try engine.removeFromSuperset(stranger) }
        #expect(throws: ActiveWorkoutError.notInActiveWorkout) { try engine.setNote("x", for: stranger) }
        #expect(throws: ActiveWorkoutError.notInActiveWorkout) { try engine.setRest(30, for: stranger) }
        #expect(throws: ActiveWorkoutError.notInActiveWorkout) { try engine.setUnit(.kg, for: stranger) }
        #expect(throws: ActiveWorkoutError.notInActiveWorkout) { try engine.setBar(.ez, weight: nil, for: stranger) }
    }

    @Test func setNoteTrimsAndClears() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        try engine.setNote("  slow tempo \n", for: rows3[0])
        #expect(rows3[0].note == "slow tempo")
        try engine.setNote("   ", for: rows3[0])
        #expect(rows3[0].note == "")
    }

    @Test func setRestChangesOnlyThatRowAndPersists() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let other = rows3[1].restSeconds
        try engine.setRest(45, for: rows3[0])
        #expect(rows3[0].restSeconds == 45)
        #expect(rows3[1].restSeconds == other)
        try engine.setRest(nil, for: rows3[0])
        #expect(rows3[0].restSeconds == nil)
        #expect(try !rig.context.hasChanges)
    }

    @Test func setUnitDoesNotConvertTheSets() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let squat = rows3[0]
        try setUpWorkingSets(engine, squat, weight: 100)
        let from = squat.unit
        let to: WeightUnit = from == .kg ? .lb : .kg
        try engine.setUnit(to, for: squat)
        #expect(squat.unit == to)
        #expect(sets(squat).allSatisfy { $0.weight == 100 })
    }

    @Test func setUnitConvertsACustomBarWeight() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let row = rows3[0]
        try engine.setUnit(.kg, for: row)
        try engine.setBar(.custom, weight: 20, for: row)
        try engine.setUnit(.lb, for: row)
        #expect(row.barWeight == round05(convert(20, from: .kg, to: .lb)))  // 44
        try engine.setUnit(.lb, for: row)
        #expect(row.barWeight == 44)
        try engine.setUnit(.kg, for: row)
        #expect(row.barWeight == 20)
        try engine.setBar(.ez, weight: nil, for: row)
        try engine.setUnit(.lb, for: row)
        #expect(row.barWeight == nil)
    }

    @Test func setBarWritesTypeAndCustomWeight() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        try engine.setBar(.custom, weight: 15, for: rows3[0])
        #expect(rows3[0].barType == .custom && rows3[0].barWeight == 15)
        try engine.setBar(.none, weight: nil, for: rows3[0])
        #expect(rows3[0].barType == BarType.none && rows3[0].barWeight == nil)
    }

    @Test func aSingleValueEditKeepsItsValueWhenTheSaveFails() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        engine.saveHook = { throw BlockEditSaveFailed() }
        #expect(throws: BlockEditSaveFailed.self) { try engine.setNote("kept", for: rows3[0]) }
        #expect(throws: BlockEditSaveFailed.self) { try engine.setRest(77, for: rows3[0]) }
        #expect(throws: BlockEditSaveFailed.self) { try engine.setBar(.ez, weight: nil, for: rows3[0]) }
        #expect(rows3[0].note == "kept" && rows3[0].restSeconds == 77 && rows3[0].barType == .ez)
    }

    @Test func replaceExerciseKeepsTheRowsSets() throws {
        let (rig, engine, rows3) = try threeRows()
        defer { withExtendedLifetime(rig) {} }
        let squat = rows3[0]
        try setUpWorkingSets(engine, squat, weight: 100)
        let ids = sets(squat).map(\.id)
        try engine.replaceExercise(squat, with: try rig.info(LibraryFixture.curl))
        #expect(squat.exerciseID == LibraryFixture.curl)
        #expect(sets(squat).map(\.id) == ids)
    }
}

private struct BlockEditSaveFailed: Error {}
