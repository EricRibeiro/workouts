#if DEBUG
    import ActivityKit
    import SwiftUI
    import WidgetKit
    import WorkoutsKit

    extension WorkoutActivityState {
        static var sampleResting: WorkoutActivityState {
            WorkoutActivityState(
                workoutName: "Push Day",
                startedAt: .now.addingTimeInterval(-1_520),
                restEndsAt: .now.addingTimeInterval(74),
                restTotal: 120,
                setsDone: 5,
                setsTotal: 14,
                current: WorkoutActivitySet(
                    setID: UUID(),
                    exerciseName: "Bench Press (Barbell)",
                    number: 3,
                    count: 4,
                    weight: 27.5,
                    unit: .lb,
                    reps: 8
                )
            )
        }

        /// The rest ended a moment ago and the app is not running to say so: the views derive "rest over" from the
        /// end date (in the app the same happens through `context.isStale`, which previews cannot set).
        static var sampleRestOver: WorkoutActivityState {
            WorkoutActivityState(
                workoutName: "Push Day",
                startedAt: .now.addingTimeInterval(-1_620),
                restEndsAt: .now.addingTimeInterval(-6),
                restTotal: 120,
                setsDone: 5,
                setsTotal: 14,
                current: WorkoutActivitySet(
                    setID: UUID(),
                    exerciseName: "Bench Press (Barbell)",
                    number: 3,
                    count: 5,
                    weight: 27.5,
                    unit: .kg,
                    reps: 8
                )
            )
        }

        static var sampleLogging: WorkoutActivityState {
            WorkoutActivityState(
                workoutName: "Push Day",
                startedAt: .now.addingTimeInterval(-1_520),
                setsDone: 5,
                setsTotal: 14,
                current: WorkoutActivitySet(
                    setID: UUID(),
                    exerciseName: "Incline Dumbbell Press",
                    number: 1,
                    count: 3,
                    weight: 60,
                    unit: .lb,
                    reps: 10
                )
            )
        }

        /// Past an hour: the expanded Island's elapsed time must show "1:00:20" whole.
        static var sampleHourLogging: WorkoutActivityState {
            var state = WorkoutActivityState.sampleLogging
            state.startedAt = .now.addingTimeInterval(-3_620)
            return state
        }

        static var sampleAllDone: WorkoutActivityState {
            WorkoutActivityState(
                workoutName: "Push Day",
                startedAt: .now.addingTimeInterval(-3_900),
                setsDone: 14,
                setsTotal: 14
            )
        }

        static var sampleLongNames: WorkoutActivityState {
            WorkoutActivityState(
                workoutName: "Upper Body Hypertrophy Block, Week Six",
                startedAt: .now.addingTimeInterval(-600),
                restEndsAt: .now.addingTimeInterval(45),
                restTotal: 90,
                setsDone: 2,
                setsTotal: 12,
                current: WorkoutActivitySet(
                    setID: UUID(),
                    exerciseName: "Single-Arm Cable Crossover Fly, Low to High (Neutral Grip)",
                    number: 2,
                    count: 4,
                    kind: .warmup,
                    weight: 102.5,
                    unit: .lb,
                    reps: 12,
                    isEmpty: true
                )
            )
        }
    }

    private let previewAttributes = WorkoutActivityAttributes(workoutID: UUID())

    #Preview("Expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
        WorkoutLiveActivity()
    } contentStates: {
        WorkoutActivityState.sampleResting
        WorkoutActivityState.sampleRestOver
        WorkoutActivityState.sampleLogging
        WorkoutActivityState.sampleAllDone
        WorkoutActivityState.sampleLongNames
        WorkoutActivityState.sampleHourLogging
    }

    // `isDynamicIslandLimitedInWidth` is read-only, so the closed Duo's narrow Island cannot be previewed; it is
    // proven on the Duo with a Live Activity running (`./dev home`). A widget extension hosts only widget previews, so the
    // narrow stack cannot be a plain-view preview either.
    #Preview("Lock Screen", as: .content, using: previewAttributes) {
        WorkoutLiveActivity()
    } contentStates: {
        WorkoutActivityState.sampleResting
        WorkoutActivityState.sampleRestOver
        WorkoutActivityState.sampleLogging
        WorkoutActivityState.sampleAllDone
        WorkoutActivityState.sampleLongNames
    }

    #Preview("Compact", as: .dynamicIsland(.compact), using: previewAttributes) {
        WorkoutLiveActivity()
    } contentStates: {
        WorkoutActivityState.sampleResting
        WorkoutActivityState.sampleRestOver
        WorkoutActivityState.sampleLogging
    }

    #Preview("Minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
        WorkoutLiveActivity()
    } contentStates: {
        WorkoutActivityState.sampleResting
        WorkoutActivityState.sampleRestOver
        WorkoutActivityState.sampleLogging
    }
#endif
