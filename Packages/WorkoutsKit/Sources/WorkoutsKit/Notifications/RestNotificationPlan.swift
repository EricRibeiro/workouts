import Foundation

/// A button on the rest-end notification.
public nonisolated enum RestNotificationAction: String, CaseIterable, Sendable {
    /// Ends the rest (`ActiveWorkoutEngine.skipRest()`).
    case skip
    /// Adds 30 seconds to the rest (`ActiveWorkoutEngine.adjustRest(by: 30)`).
    case add30

    /// Seconds ``add30`` adds.
    public static let addSeconds = 30

    public var title: String {
        switch self {
        case .skip: "Skip"
        case .add30: "+30 s"
        }
    }
}

/// What the rest-end local notification should look like right now, derived from the engine. The app turns it into a
/// `UNNotificationRequest`; everything testable lives here (Foundation only).
///
/// There is one in-progress workout and one rest, so the identifier is a constant: scheduling a plan replaces the
/// previous request, and "no plan" removes it without the notifier having to remember anything across relaunches.
public nonisolated struct RestNotificationPlan: Equatable, Sendable {
    public static let identifier = "workouts.rest-end"
    public static let categoryIdentifier = "workouts.rest-end"
    /// The part of the body that precedes the next set.
    public static let bodyPrefix = "Rest over"
    /// Body suffix when no set is left to do ("Rest over · All sets done").
    public static let noNextSetText = "All sets done"

    public var identifier: String { Self.identifier }
    public var categoryIdentifier: String { Self.categoryIdentifier }
    /// The next exercise's name, else the workout's name.
    public var title: String
    /// "Rest over · Set 3 · 27.5 lb × 8" (``WorkoutActivitySet/nextSetText``); "Rest over · All sets done" when every
    /// set is checked.
    public var body: String
    /// When the notification fires: the rest's end (`restEndsAt`), so it follows +10/+30 and disappears on skip.
    public var fireDate: Date
    /// The buttons, in display order.
    public var actions: [RestNotificationAction] { RestNotificationAction.allCases }

    public init(title: String, body: String, fireDate: Date) {
        self.title = title
        self.body = body
        self.fireDate = fireDate
    }

    /// The plan for `state`; nil when there is no workout or no rest is running.
    public init?(state: WorkoutActivityState?) {
        guard let state, let endsAt = state.restEndsAt else { return nil }
        if let next = state.current {
            self.init(title: next.exerciseName, body: "\(Self.bodyPrefix) · \(next.nextSetText)", fireDate: endsAt)
        } else {
            self.init(
                title: state.workoutName,
                body: "\(Self.bodyPrefix) · \(Self.noNextSetText)",
                fireDate: endsAt
            )
        }
    }
}

extension ActiveWorkoutEngine {
    /// What should be scheduled for the running rest; nil when no rest runs (or no workout). Reads the same state the
    /// Live Activity does, so observing it re-evaluates after any change that moves the rest or the next set.
    public var restNotificationPlan: RestNotificationPlan? {
        RestNotificationPlan(state: activityState)
    }
}
