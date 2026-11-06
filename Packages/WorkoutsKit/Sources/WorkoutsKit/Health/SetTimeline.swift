import Foundation

/// A finished workout's own timeline for the heart-rate chart: where each exercise block and each completed set fall,
/// in seconds from an origin date. Pass the Fitness workout's start as the origin to share the heart-rate series' axis;
/// pass the workout's own start for offsets from our workout.
public nonisolated struct SetTimeline: Hashable, Sendable {
    /// An exercise block spanning its first to its last completed set. All exercises of one superset are merged into a
    /// single block named "Superset N" (the number the logging screen shows), so interleaved sets do not interleave bands.
    public struct Block: Hashable, Sendable {
        public var name: String
        public var start: TimeInterval
        public var end: TimeInterval
        /// The superset's display number, nil for a plain exercise.
        public var supersetNumber: Int?
        public var isSuperset: Bool { supersetNumber != nil }
        /// The exercises whose sets fall in this block: just `name` for a plain block, every member for a superset.
        public var exerciseNames: [String]

        public init(
            name: String,
            start: TimeInterval,
            end: TimeInterval,
            supersetNumber: Int? = nil,
            exerciseNames: [String]? = nil
        ) {
            self.name = name
            self.start = start
            self.end = end
            self.supersetNumber = supersetNumber
            self.exerciseNames = exerciseNames ?? [name]
        }
    }

    /// One completed set, at the moment it was completed.
    public struct Tick: Hashable, Sendable {
        public var offset: TimeInterval
        public var blockName: String
        /// 1-based position of the set in its block, counting sets that were not completed.
        public var setNumber: Int

        public init(offset: TimeInterval, blockName: String, setNumber: Int) {
            self.offset = offset
            self.blockName = blockName
            self.setNumber = setNumber
        }
    }

    /// Plain input for one exercise block: its name, its raw superset group (nil = none) and each set's `completedAt` in
    /// set order (nil = not completed).
    public struct BlockInput: Hashable, Sendable {
        public var name: String
        public var supersetGroup: Int?
        public var completions: [Date?]

        public init(name: String, supersetGroup: Int? = nil, completions: [Date?]) {
            self.name = name
            self.supersetGroup = supersetGroup
            self.completions = completions
        }
    }

    public var blocks: [Block]
    public var setTicks: [Tick]

    public init(blocks: [Block] = [], setTicks: [Tick] = []) {
        self.blocks = blocks
        self.setTicks = setTicks
    }

    public var isEmpty: Bool { blocks.isEmpty }

    /// Builds the timeline. Blocks keep the order given (a superset sits where its first member does); a block without a
    /// completed set is skipped; ticks are sorted by time. Exercises of one superset (numbered as in
    /// `SetTableLayout.supersetNumbers`) merge into one block from the first to the last completed set of any member.
    /// Offsets are not clamped, so a set completed before `origin` has a negative offset.
    public static func make(origin: Date, blocks inputs: [BlockInput]) -> SetTimeline {
        let numbers = SetTableLayout.supersetNumbers(for: inputs.map(\.supersetGroup))
        var blocks: [Block] = []
        var ticks: [Tick] = []
        var offsetsByInput: [[TimeInterval]] = []
        for input in inputs {
            var offsets: [TimeInterval] = []
            for (index, completedAt) in input.completions.enumerated() {
                guard let completedAt else { continue }
                let offset = completedAt.timeIntervalSince(origin)
                offsets.append(offset)
                ticks.append(Tick(offset: offset, blockName: input.name, setNumber: index + 1))
            }
            offsetsByInput.append(offsets)
        }
        var emitted: Set<Int> = []
        for (index, input) in inputs.enumerated() {
            if let number = numbers[index] {
                guard emitted.insert(number).inserted else { continue }
                let members = inputs.indices.filter { numbers[$0] == number && !offsetsByInput[$0].isEmpty }
                let all = members.flatMap { offsetsByInput[$0] }
                guard let first = all.min(), let last = all.max() else { continue }
                blocks.append(
                    Block(
                        name: "Superset \(number)",
                        start: first,
                        end: last,
                        supersetNumber: number,
                        exerciseNames: members.map { inputs[$0].name }
                    )
                )
            } else if let first = offsetsByInput[index].min(), let last = offsetsByInput[index].max() {
                blocks.append(Block(name: input.name, start: first, end: last))
            }
        }
        ticks.sort { $0.offset < $1.offset }
        return SetTimeline(blocks: blocks, setTicks: ticks)
    }

    /// The block holding `offset` (inclusive of its ends), if any; the first match when blocks overlap.
    public func block(at offset: TimeInterval) -> Block? {
        blocks.first { $0.start <= offset && offset <= $0.end }
    }

    /// The tick nearest `offset`, if any.
    public func nearestTick(to offset: TimeInterval) -> Tick? {
        setTicks.min { abs($0.offset - offset) < abs($1.offset - offset) }
    }

    /// The set a chart selection means: the nearest tick, when `offset` falls inside that tick's block.
    public func set(at offset: TimeInterval) -> Tick? {
        guard let block = block(at: offset) else { return nil }
        return setTicks.filter {
            block.exerciseNames.contains($0.blockName) && block.start <= $0.offset && $0.offset <= block.end
        }
        .min { abs($0.offset - offset) < abs($1.offset - offset) }
    }
}

extension SetTimeline {
    /// The timeline of a workout's completed sets, blocks by `position`, sets by `position`.
    public static func make(workout: Workout, origin: Date? = nil) -> SetTimeline {
        let blocks = (workout.exercises ?? []).sorted { $0.position < $1.position }.map { block in
            BlockInput(
                name: block.exerciseName,
                supersetGroup: block.supersetGroup,
                completions: (block.sets ?? []).sorted { $0.position < $1.position }.map { set in
                    set.completed ? set.completedAt : nil
                }
            )
        }
        return make(origin: origin ?? workout.startedAt, blocks: blocks)
    }
}
