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
}
