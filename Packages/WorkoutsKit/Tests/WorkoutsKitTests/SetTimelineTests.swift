import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct SetTimelineTests {
    private static let origin = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private static func at(_ seconds: TimeInterval) -> Date { origin.addingTimeInterval(seconds) }

    @Test func blocksSpanFirstToLastCompletedSetInOrder() {
        let timeline = SetTimeline.make(
            origin: Self.origin,
            blocks: [
                .init(name: "Bench Press", completions: [Self.at(60), Self.at(180), Self.at(300)]),
                .init(name: "Row", completions: [Self.at(420), Self.at(540)]),
            ]
        )
        #expect(
            timeline.blocks == [
                .init(name: "Bench Press", start: 60, end: 300),
                .init(name: "Row", start: 420, end: 540),
            ]
        )
        #expect(timeline.setTicks.map(\.offset) == [60, 180, 300, 420, 540])
        #expect(timeline.setTicks.map(\.setNumber) == [1, 2, 3, 1, 2])
        #expect(timeline.setTicks.last?.blockName == "Row")
    }

    @Test func blocksWithoutCompletedSetsAreSkipped() {
        let timeline = SetTimeline.make(
            origin: Self.origin,
            blocks: [
                .init(name: "Skipped", completions: [nil, nil]),
                .init(name: "Empty", completions: []),
                .init(name: "Curl", completions: [nil, Self.at(90)]),
            ]
        )
        #expect(timeline.blocks == [.init(name: "Curl", start: 90, end: 90)])
        // The set number counts sets that were not completed.
        #expect(timeline.setTicks == [.init(offset: 90, blockName: "Curl", setNumber: 2)])
    }

    @Test func emptyInputIsEmpty() {
        let timeline = SetTimeline.make(origin: Self.origin, blocks: [])
        #expect(timeline.isEmpty)
        #expect(timeline.setTicks.isEmpty)
        #expect(timeline.block(at: 10) == nil)
        #expect(timeline.nearestTick(to: 10) == nil)
        #expect(timeline.set(at: 10) == nil)
    }

    @Test func ticksAreSortedByTimeAcrossInterleavedBlocks() {
        let timeline = SetTimeline.make(
            origin: Self.origin,
            blocks: [
                .init(name: "A", completions: [Self.at(100), Self.at(300)]),
                .init(name: "B", completions: [Self.at(200), Self.at(400)]),
            ]
        )
        #expect(timeline.setTicks.map(\.blockName) == ["A", "B", "A", "B"])
    }

    @Test func selectionResolvesSetOnlyInsideItsBlock() {
        let timeline = SetTimeline.make(
            origin: Self.origin,
            blocks: [
                .init(name: "Bench", completions: [Self.at(60), Self.at(180)]),
                .init(name: "Row", completions: [Self.at(400), Self.at(500)]),
            ]
        )
        #expect(timeline.set(at: 100) == .init(offset: 60, blockName: "Bench", setNumber: 1))
        #expect(timeline.set(at: 170)?.setNumber == 2)
        #expect(timeline.set(at: 250) == nil)
        #expect(timeline.nearestTick(to: 250)?.blockName == "Bench")
        #expect(timeline.block(at: 450)?.name == "Row")
    }

    @Test func supersetExercisesMergeIntoOneBlockAmongPlainOnes() {
        let timeline = SetTimeline.make(
            origin: Self.origin,
            blocks: [
                .init(name: "Squat", completions: [Self.at(60), Self.at(120)]),
                .init(
                    name: "Lateral Raise",
                    supersetGroup: 9,
                    completions: [Self.at(200), Self.at(320), Self.at(440)]
                ),
                .init(name: "Pushdown", supersetGroup: 9, completions: [Self.at(260), Self.at(380), Self.at(500)]),
                .init(name: "Curl", completions: [Self.at(600)]),
            ]
        )
        #expect(
            timeline.blocks == [
                .init(name: "Squat", start: 60, end: 120),
                .init(
                    name: "Superset 1",
                    start: 200,
                    end: 500,
                    supersetNumber: 1,
                    exerciseNames: ["Lateral Raise", "Pushdown"]
                ),
                .init(name: "Curl", start: 600, end: 600),
            ]
        )
        #expect(timeline.blocks.map(\.isSuperset) == [false, true, false])
        #expect(timeline.setTicks.count == 9)
    }

    @Test func secondSupersetIsNumberedTwoAndSingleMemberGroupIsPlain() {
        let timeline = SetTimeline.make(
            origin: Self.origin,
            blocks: [
                .init(name: "A", supersetGroup: 4, completions: [Self.at(10)]),
                .init(name: "B", supersetGroup: 4, completions: [Self.at(20)]),
                .init(name: "C", supersetGroup: 7, completions: [Self.at(30)]),
                .init(name: "D", supersetGroup: 7, completions: [Self.at(40)]),
                .init(name: "Lone", supersetGroup: 2, completions: [Self.at(50)]),
            ]
        )
        #expect(timeline.blocks.map(\.name) == ["Superset 1", "Superset 2", "Lone"])
        #expect(timeline.blocks.map(\.isSuperset) == [true, true, false])
    }

    @Test func selectionInsideSupersetNamesTheExerciseOfThatSet() {
        let timeline = SetTimeline.make(
            origin: Self.origin,
            blocks: [
                .init(name: "Raise", supersetGroup: 1, completions: [Self.at(100), Self.at(300)]),
                .init(name: "Pushdown", supersetGroup: 1, completions: [Self.at(200), Self.at(400)]),
            ]
        )
        #expect(timeline.blocks.count == 1)
        #expect(timeline.set(at: 205) == .init(offset: 200, blockName: "Pushdown", setNumber: 1))
        #expect(timeline.set(at: 290) == .init(offset: 300, blockName: "Raise", setNumber: 2))
    }

    @Test func offsetsBeforeTheOriginAreNegative() {
        let timeline = SetTimeline.make(origin: Self.origin, blocks: [.init(name: "A", completions: [Self.at(-30)])])
        #expect(timeline.setTicks.first?.offset == -30)
    }

    @Test func workoutOverloadSortsByPositionAndSkipsIncompleteSets() {
        let workout = Workout(startedAt: Self.origin)
        let second = WorkoutExercise(exerciseName: "Row", position: 1)
        let first = WorkoutExercise(exerciseName: "Bench", position: 0)
        first.sets = [
            WorkoutSet(position: 1, completed: true, completedAt: Self.at(200)),
            WorkoutSet(position: 0, completed: true, completedAt: Self.at(100)),
            WorkoutSet(position: 2, completed: false, completedAt: nil),
        ]
        second.sets = [WorkoutSet(position: 0, completed: true, completedAt: Self.at(300))]
        workout.exercises = [second, first]

        let timeline = SetTimeline.make(workout: workout)
        #expect(timeline.blocks.map(\.name) == ["Bench", "Row"])
        #expect(timeline.setTicks.map(\.offset) == [100, 200, 300])
        #expect(timeline.setTicks.map(\.setNumber) == [1, 2, 1])
    }
}
