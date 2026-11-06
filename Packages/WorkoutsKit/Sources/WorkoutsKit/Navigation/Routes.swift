import Foundation

/// The selectable tabs: the three top-level ones, in Eric's order (DECISIONS "Navigation and layout": History · Workout ·
/// Exercises). The tab bar is the system's (the trailing strip on the Duo's closed display); there is no app sidebar (JC52).
public enum AppTab: Hashable, Sendable {
    case history
    case workout
    case exercises

    /// The tabs of the compact bar, in order.
    public static let main: [AppTab] = [.history, .workout, .exercises]

    /// Workout is the default selection (DECISIONS "Navigation and layout").
    public static let `default`: AppTab = .workout
}

// Routes carry ids only, never model objects, so they survive relaunch and can be built from a Live Activity
// button or a notification action without a model context. The views resolve the id against SwiftData.

/// Destinations pushed on the History tab's stack.
public enum HistoryRoute: Hashable, Codable, Sendable {
    /// Workout detail (PLAN section 3 History tab, 5.5): rows push it with a zoom transition. The past-workout editor
    /// (5.6) is not a route: it is a modal cover over the detail or the list.
    case workout(UUID)
}

/// Destinations pushed on the Workout tab's stack.
public enum WorkoutRoute: Hashable, Codable, Sendable {
    /// Template preview, pushed on regular width (compact uses a sheet; PLAN 3.3). Also the target of
    /// "open a template" from a notification or Live Activity (DECISIONS `AppNavigation` line).
    case template(UUID)
    /// Template editor, pushed in both widths (PLAN 3.4).
    case editTemplate(UUID)
}

/// Destinations pushed on the Exercises tab's stack (the detail column of its `NavigationSplitView`; compact pushes).
public enum ExercisesRoute: Hashable, Codable, Sendable {
    /// Exercise detail (PLAN 4.2): About · History · Charts · Records.
    case exercise(UUID)
}
