import Foundation

/// A finished workout's own timeline for the heart-rate chart: where each exercise block and each completed set fall,
/// in seconds from an origin date. Pass the Fitness workout's start as the origin to share the heart-rate series' axis;
/// pass the workout's own start for offsets from our workout.
public nonisolated struct SetTimeline: Hashable, Sendable {
    /// An exercise block spanning its first to its last completed set.
    public struct Block: Hashable, Sendable {
        public var name: String
        public var start: TimeInterval
        public var end: TimeInterval

        public init(name: String, start: TimeInterval, end: TimeInterval) {
            self.name = name
            self.start = start
            self.end = end
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

    /// Plain input for one exercise block: its name and each set's `completedAt` in set order (nil = not completed).
    public struct BlockInput: Hashable, Sendable {
        public var name: String
        public var completions: [Date?]

        public init(name: String, completions: [Date?]) {
            self.name = name
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

    /// Builds the timeline. Blocks keep the order given; a block without a completed set is skipped; ticks are sorted by
    /// time. Offsets are not clamped, so a set completed before `origin` has a negative offset.
    public static func make(origin: Date, blocks inputs: [BlockInput]) -> SetTimeline {
        var blocks: [Block] = []
        var ticks: [Tick] = []
        for input in inputs {
            var offsets: [TimeInterval] = []
            for (index, completedAt) in input.completions.enumerated() {
                guard let completedAt else { continue }
                let offset = completedAt.timeIntervalSince(origin)
                offsets.append(offset)
                ticks.append(Tick(offset: offset, blockName: input.name, setNumber: index + 1))
            }
            guard let first = offsets.min(), let last = offsets.max() else { continue }
            blocks.append(Block(name: input.name, start: first, end: last))
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
        return setTicks.filter { $0.blockName == block.name && block.start <= $0.offset && $0.offset <= block.end }
            .min { abs($0.offset - offset) < abs($1.offset - offset) }
    }
}

extension SetTimeline {
    /// The timeline of a workout's completed sets, blocks by `position`, sets by `position`.
    public static func make(workout: Workout, origin: Date? = nil) -> SetTimeline {
        let blocks = (workout.exercises ?? []).sorted { $0.position < $1.position }.map { block in
            BlockInput(
                name: block.exerciseName,
                completions: (block.sets ?? []).sorted { $0.position < $1.position }.map { set in
                    set.completed ? set.completedAt : nil
                }
            )
        }
        return make(origin: origin ?? workout.startedAt, blocks: blocks)
    }
}
