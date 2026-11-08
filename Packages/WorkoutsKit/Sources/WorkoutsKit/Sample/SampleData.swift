import Foundation
import SwiftData

/// Deterministic demo data for previews, the preview gallery and the debug "Load sample data" button.
///
/// Two folders, three templates (Push, Pull, Legs), one custom exercise and 50 finished workouts
/// spread over roughly the last six months, all weights in kg. No in-progress workout.
public enum SampleData {
    /// How many finished workouts `seed` inserts.
    public static let finishedWorkoutCount = 50

    /// Name of the one custom exercise `seed` inserts.
    public static let customExerciseName = "Sled Push"

    /// Inserts the sample data into `context` and saves. The same `seed` and `now` always produce the same dates,
    /// weights and ids. Calling it twice on one context inserts the data twice.
    ///
    /// - Parameters:
    ///   - catalog: Where exercises are picked from by name; a name the catalog lacks falls back to the first
    ///     unused strength exercise.
    ///   - now: Every workout ends before the start of this day.
    ///   - workoutCount: How many finished workouts to insert (default `finishedWorkoutCount`); the performance runs
    ///     scale it up.
    ///   - spanDays: When set, the workouts are spread evenly over this many days back from `now` instead of every
    ///     2 to 3 days.
    public static func seed(
        into context: ModelContext,
        catalog: LibraryCatalog,
        now: Date = .now,
        seed: UInt64 = 1,
        workoutCount: Int = finishedWorkoutCount,
        spanDays: Int? = nil
    ) throws {
        var builder = SampleBuilder(catalog: catalog, now: now, random: SplitMix64(state: seed))
        builder.workoutCount = max(workoutCount, 0)
        builder.spanDays = spanDays
        builder.build(into: context)
        try context.save()
    }
}

extension ModelContainer {
    /// An in-memory, non-CloudKit container filled by `SampleData.seed`. For previews, the gallery and tests.
    public static func preview(catalog: LibraryCatalog) throws -> ModelContainer {
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        try SampleData.seed(into: container.mainContext, catalog: catalog)
        return container
    }
}

// MARK: - Random numbers

/// SplitMix64: tiny, fixed algorithm, so the same seed gives the same data on every Swift version.
struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `0..<bound` (`bound > 0`).
    mutating func below(_ bound: Int) -> Int {
        Int(next() % UInt64(max(bound, 1)))
    }

    /// True `percent` times out of 100.
    mutating func chance(_ percent: Int) -> Bool {
        below(100) < percent
    }

    mutating func uuid() -> UUID {
        let high = next()
        let low = next()
        var bytes: [UInt8] = []
        for word in [high, low] {
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8(truncatingIfNeeded: word >> UInt64(shift)))
            }
        }
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }
}

// MARK: - Plans

/// One exercise of a day: where it starts, how it progresses, what a session looks like.
private struct LiftPlan {
    var name: String
    var startWeight: Double
    /// Added to the working weight after a successful session.
    var increment: Double
    var sets: Int
    var reps: Int
    var warmups: Int
    var supersetGroup: Int?
    var restSeconds: Int
}

private struct DayPlan {
    var name: String
    var note: String
    var folder: Int
    var lifts: [LiftPlan]
}

private let folderNames = ["Upper Body", "Lower Body"]

private let dayPlans: [DayPlan] = [
    DayPlan(
        name: "Push",
        note: "Chest, shoulders, triceps.",
        folder: 0,
        lifts: [
            LiftPlan(
                name: "Barbell Bench Press",
                startWeight: 60,
                increment: 2.5,
                sets: 4,
                reps: 6,
                warmups: 2,
                supersetGroup: nil,
                restSeconds: 150
            ),
            LiftPlan(
                name: "Lever Seated Hammer Grip Shoulder Press",
                startWeight: 35,
                increment: 1.25,
                sets: 3,
                reps: 8,
                warmups: 1,
                supersetGroup: nil,
                restSeconds: 120
            ),
            LiftPlan(
                name: "Incline Dumbbell Bench Press",
                startWeight: 20,
                increment: 1,
                sets: 3,
                reps: 10,
                warmups: 0,
                supersetGroup: nil,
                restSeconds: 90
            ),
            LiftPlan(
                name: "Cable Triceps Pushdown",
                startWeight: 25,
                increment: 2.5,
                sets: 3,
                reps: 12,
                warmups: 0,
                supersetGroup: 1,
                restSeconds: 60
            ),
            LiftPlan(
                name: "Dumbbell Lateral Raise",
                startWeight: 8,
                increment: 1,
                sets: 3,
                reps: 15,
                warmups: 0,
                supersetGroup: 1,
                restSeconds: 60
            ),
        ]
    ),
    DayPlan(
        name: "Pull",
        note: "Back and biceps.",
        folder: 0,
        lifts: [
            LiftPlan(
                name: "Deadlift",
                startWeight: 90,
                increment: 5,
                sets: 3,
                reps: 5,
                warmups: 2,
                supersetGroup: nil,
                restSeconds: 180
            ),
            LiftPlan(
                name: "Pull-Up",
                startWeight: 0,
                increment: 0,
                sets: 3,
                reps: 6,
                warmups: 0,
                supersetGroup: nil,
                restSeconds: 120
            ),
            LiftPlan(
                name: "Seated Cable Low Row Neutral Grip",
                startWeight: 50,
                increment: 2.5,
                sets: 4,
                reps: 8,
                warmups: 1,
                supersetGroup: nil,
                restSeconds: 120
            ),
            LiftPlan(
                name: "Cable Lat Pulldown",
                startWeight: 45,
                increment: 2.5,
                sets: 3,
                reps: 10,
                warmups: 0,
                supersetGroup: nil,
                restSeconds: 90
            ),
            LiftPlan(
                name: "Cable Face Pull",
                startWeight: 20,
                increment: 2.5,
                sets: 3,
                reps: 15,
                warmups: 0,
                supersetGroup: nil,
                restSeconds: 60
            ),
            LiftPlan(
                name: "Dumbbell Biceps Curl",
                startWeight: 10,
                increment: 1,
                sets: 3,
                reps: 12,
                warmups: 0,
                supersetGroup: nil,
                restSeconds: 60
            ),
        ]
    ),
    DayPlan(
        name: "Legs",
        note: "Squat first, then accessories.",
        folder: 1,
        lifts: [
            LiftPlan(
                name: "Barbell Squat",
                startWeight: 70,
                increment: 2.5,
                sets: 4,
                reps: 6,
                warmups: 2,
                supersetGroup: nil,
                restSeconds: 180
            ),
            LiftPlan(
                name: "Romanian Deadlift",
                startWeight: 60,
                increment: 2.5,
                sets: 3,
                reps: 8,
                warmups: 1,
                supersetGroup: nil,
                restSeconds: 120
            ),
            LiftPlan(
                name: "Leg Press",
                startWeight: 100,
                increment: 5,
                sets: 3,
                reps: 10,
                warmups: 0,
                supersetGroup: nil,
                restSeconds: 120
            ),
            LiftPlan(
                name: "Seated Leg Curl",
                startWeight: 30,
                increment: 2.5,
                sets: 3,
                reps: 12,
                warmups: 0,
                supersetGroup: nil,
                restSeconds: 75
            ),
            LiftPlan(
                name: "Machine Calf Raises",
                startWeight: 40,
                increment: 2.5,
                sets: 4,
                reps: 15,
                warmups: 0,
                supersetGroup: nil,
                restSeconds: 60
            ),
            LiftPlan(
                name: SampleData.customExerciseName,
                startWeight: 40,
                increment: 5,
                sets: 3,
                reps: 10,
                warmups: 0,
                supersetGroup: nil,
                restSeconds: 90
            ),
        ]
    ),
]

/// A lift resolved against the catalog, with its progression state.
private struct Lift {
    var plan: LiftPlan
    var exerciseID: UUID
    var exerciseName: String
    var weightType: WeightType
    /// Successful sessions so far.
    var progress = 0

    var hasWeight: Bool { weightType.category == .strength }
    var barType: BarType { weightType == .barbell ? .olympic : .none }

    /// The weight of a working set after `progress` successful sessions, on a 2.5 kg grid (1 kg for dumbbells).
    var workingWeight: Double? {
        guard hasWeight else { return nil }
        let raw = plan.startWeight + Double(progress) * plan.increment
        let step = plan.increment < 2.5 ? 1.0 : 2.5
        return max((raw / step).rounded() * step, step)
    }

    /// Reps for a working set: bodyweight lifts gain a rep every other success.
    var workingReps: Int {
        hasWeight ? plan.reps : plan.reps + progress / 2
    }
}

// MARK: - Builder

private struct SampleBuilder {
    let catalog: LibraryCatalog
    let now: Date
    var random: SplitMix64
    let calendar = Calendar.current
    var workoutCount = SampleData.finishedWorkoutCount
    var spanDays: Int?

    init(catalog: LibraryCatalog, now: Date, random: SplitMix64) {
        self.catalog = catalog
        self.now = now
        self.random = random
    }

    mutating func build(into context: ModelContext) {
        let starts = workoutStarts()
        let firstStart = starts.first ?? now
        let setupDate = calendar.date(byAdding: .day, value: -7, to: firstStart) ?? firstStart

        let custom = Exercise(
            id: random.uuid(),
            name: SampleData.customExerciseName,
            aliases: ["Prowler Push"],
            equipment: ["sled"],
            bodyPart: "legs",
            weightType: .weighted,
            instructions: ["Load the sled.", "Drive with low, straight arms."],
            unit: .kg,
            barType: .none,
            restSeconds: 90,
            createdAt: setupDate,
            updatedAt: setupDate
        )
        context.insert(custom)

        var folders: [TemplateFolder] = []
        for (position, name) in folderNames.enumerated() {
            let folder = TemplateFolder(
                id: random.uuid(),
                name: name,
                position: position,
                createdAt: setupDate,
                updatedAt: setupDate
            )
            context.insert(folder)
            folders.append(folder)
        }

        var templates: [Template] = []
        var lifts: [[Lift]] = []
        for (position, day) in dayPlans.enumerated() {
            let template = Template(
                id: random.uuid(),
                name: day.name,
                note: day.note,
                position: position,
                createdAt: setupDate,
                updatedAt: setupDate
            )
            context.insert(template)
            template.folder = folders[day.folder]
            templates.append(template)
            lifts.append(resolve(day, custom: custom))
        }

        // The removed sticky note drew one uuid here; keep drawing it so every later id and value stays the same
        // (snapshot references depend on this sequence).
        _ = random.uuid()

        for (offset, start) in starts.enumerated() {
            let day = offset % dayPlans.count
            addWorkout(
                at: start,
                index: offset,
                plan: dayPlans[day],
                template: templates[day],
                lifts: &lifts[day],
                into: context
            )
        }

        for (index, template) in templates.enumerated() {
            addTemplateExercises(to: template, lifts: lifts[index], date: setupDate, into: context)
        }
    }

    // MARK: Dates

    /// Start times, oldest first. Mostly 2 to 3 days apart with the odd week off; the newest is yesterday evening.
    private mutating func workoutStarts() -> [Date] {
        let today = calendar.startOfDay(for: now)
        var daysBack = 1
        var newestFirst: [Date] = []
        for index in 0..<workoutCount {
            if let spanDays {
                daysBack = 1 + Int(Double(index) * Double(spanDays) / Double(max(workoutCount, 1)))
            }
            let day = calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
            let minutes = (17 + random.below(3)) * 60 + random.below(46)
            newestFirst.append(calendar.date(byAdding: .minute, value: minutes, to: day) ?? day)
            if spanDays == nil {
                daysBack += random.chance(15) ? 7 + random.below(4) : 2 + random.below(2)
            }
        }
        return newestFirst.reversed()
    }

    // MARK: Exercises

    private func resolve(_ day: DayPlan, custom: Exercise) -> [Lift] {
        var used = Set<UUID>()
        var result: [Lift] = []
        for plan in day.lifts {
            if plan.name == custom.name {
                used.insert(custom.id)
                result.append(
                    Lift(plan: plan, exerciseID: custom.id, exerciseName: custom.name, weightType: custom.weightType)
                )
                continue
            }
            let wanted = plan.name.lowercased()
            let exact = catalog.exercises.first {
                !$0.retired && $0.name.lowercased() == wanted && !used.contains($0.id)
            }
            let fallback = catalog.exercises.first {
                !$0.retired && $0.weightType.category == .strength && !used.contains($0.id)
            }
            guard let picked = exact ?? fallback else { continue }
            used.insert(picked.id)
            result.append(
                Lift(plan: plan, exerciseID: picked.id, exerciseName: picked.name, weightType: picked.weightType)
            )
        }
        return result
    }

    // MARK: Workouts

    private mutating func addWorkout(
        at start: Date,
        index: Int,
        plan: DayPlan,
        template: Template,
        lifts: inout [Lift],
        into context: ModelContext
    ) {
        let workout = Workout(
            id: random.uuid(),
            name: plan.name,
            note: index % 10 == 7 ? "Felt strong today." : "",
            startedAt: start,
            createdAt: start,
            updatedAt: start
        )
        context.insert(workout)
        workout.template = template

        var clock = start.addingTimeInterval(120)
        for position in lifts.indices {
            if index > 0 && random.chance(75) { lifts[position].progress += 1 }
            let lift = lifts[position]
            let row = WorkoutExercise(
                id: random.uuid(),
                exerciseID: lift.exerciseID,
                exerciseName: lift.exerciseName,
                position: position,
                supersetGroup: lift.plan.supersetGroup,
                restSeconds: lift.plan.restSeconds,
                unit: .kg,
                barType: lift.barType,
                updatedAt: start
            )
            context.insert(row)
            row.workout = workout

            let specs = warmups(for: lift) + workingSets(for: lift)
            for (setPosition, spec) in specs.enumerated() {
                clock = clock.addingTimeInterval(100)
                let set = WorkoutSet(
                    id: random.uuid(),
                    position: setPosition,
                    kind: spec.kind,
                    weight: spec.weight,
                    reps: spec.reps,
                    completed: true,
                    completedAt: clock,
                    rpe: spec.rpe
                )
                context.insert(set)
                set.workoutExercise = row
            }
        }
        let finish = clock.addingTimeInterval(120)
        workout.finishedAt = finish
        workout.updatedAt = finish
    }

    private struct SetSpec {
        var kind: SetKind
        var weight: Double?
        var reps: Int
        var rpe: Double?
    }

    private func warmups(for lift: Lift) -> [SetSpec] {
        guard let work = lift.workingWeight, lift.plan.warmups > 0 else { return [] }
        return (0..<lift.plan.warmups).map { step in
            let fraction = 0.4 + 0.2 * Double(step)
            let weight = max((work * fraction / 2.5).rounded() * 2.5, 20)
            return SetSpec(kind: .warmup, weight: weight, reps: step == 0 ? 8 : 5, rpe: nil)
        }
    }

    private mutating func workingSets(for lift: Lift) -> [SetSpec] {
        var specs: [SetSpec] = []
        for number in 0..<lift.plan.sets {
            let isLast = number == lift.plan.sets - 1
            let reps = max(lift.workingReps - (random.chance(30) ? 1 : 0), 1)
            var spec = SetSpec(kind: .normal, weight: lift.workingWeight, reps: reps, rpe: nil)
            if isLast {
                spec.rpe = random.chance(50) ? 8 : 9
                if lift.hasWeight, lift.plan.warmups == 0, random.chance(20), let weight = lift.workingWeight {
                    spec.kind = .drop
                    spec.weight = max((weight * 0.8 / 2.5).rounded() * 2.5, 2.5)
                    spec.reps = reps + 3
                } else if random.chance(8) {
                    spec.kind = .failure
                    spec.reps = max(reps - 2, 1)
                }
            }
            specs.append(spec)
        }
        return specs
    }

    // MARK: Templates

    /// Planned sets are the final working weights, so starting a workout from a template feels current.
    private mutating func addTemplateExercises(
        to template: Template,
        lifts: [Lift],
        date: Date,
        into context: ModelContext
    ) {
        for (position, lift) in lifts.enumerated() {
            let row = TemplateExercise(
                id: random.uuid(),
                exerciseID: lift.exerciseID,
                exerciseName: lift.exerciseName,
                position: position,
                supersetGroup: lift.plan.supersetGroup,
                restSeconds: lift.plan.restSeconds,
                unit: .kg,
                barType: lift.barType,
                updatedAt: date
            )
            context.insert(row)
            row.template = template

            var specs = warmups(for: lift)
            for _ in 0..<lift.plan.sets {
                specs.append(SetSpec(kind: .normal, weight: lift.workingWeight, reps: lift.workingReps, rpe: nil))
            }
            for (setPosition, spec) in specs.enumerated() {
                let set = TemplateSet(
                    id: random.uuid(),
                    position: setPosition,
                    kind: spec.kind,
                    weight: spec.weight,
                    reps: spec.reps
                )
                context.insert(set)
                set.templateExercise = row
            }
        }
    }
}
