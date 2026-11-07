import Foundation
import Observation

/// Navigation state for the whole app: selected tab, one typed stack per tab, the Settings sheet and the
/// active-workout cover. Views bind to it; Live Activity buttons and notification actions drive it through the
/// intent methods (DECISIONS "Navigation and layout", `AppNavigation` line).
@Observable
public final class AppNavigation {
    /// The selected tab. Set through `select(_:)` so reselecting pops to root.
    public private(set) var selectedTab: AppTab

    public var historyPath: [HistoryRoute]
    public var workoutPath: [WorkoutRoute]
    public var exercisesPath: [ExercisesRoute]

    /// The Settings `Form` sheet, opened from the Workout tab's gear.
    public var isSettingsPresented: Bool

    /// The active workout's `fullScreenCover` on the root `TabView`, not tied to any tab.
    public var isWorkoutCoverPresented: Bool

    /// Whether the cover is actually on screen (set from its `onAppear`/`onDisappear`). `isWorkoutCoverPresented` is only
    /// the request: a cover cannot present while a sheet is up, and then the request stays true with nothing showing. The
    /// resume ring keys off this, so the person always has the cover or the ring.
    public var isWorkoutCoverOnScreen = false

    /// Whether a past-workout or template editor (a full-screen cover hosted by a tab) is on screen, set from the editor's
    /// `onAppear`/`onDisappear` through `setEditorCoverOnScreen(_:)`. The editor may hold unsaved edits and the workout
    /// cover presented over it would tear it down, so `openActiveWorkout()` waits while this is true.
    public private(set) var isEditorCoverOnScreen = false

    /// An open-the-workout request (Live Activity, rest notification) deferred because an editor was up; it is fulfilled
    /// when the editor goes away.
    public private(set) var isWorkoutOpenPending = false

    /// A workout is running but its cover is dismissed (DECISIONS: Minimise "dismisses the cover; the resume
    /// control restores it; a running workout survives any tab change"). Drives the ring `ToolbarItem`.
    public private(set) var isWorkoutMinimised: Bool

    public init(
        selectedTab: AppTab = .default,
        historyPath: [HistoryRoute] = [],
        workoutPath: [WorkoutRoute] = [],
        exercisesPath: [ExercisesRoute] = [],
        isSettingsPresented: Bool = false,
        isWorkoutCoverPresented: Bool = false,
        isWorkoutMinimised: Bool = false
    ) {
        self.selectedTab = selectedTab
        self.historyPath = historyPath
        self.workoutPath = workoutPath
        self.exercisesPath = exercisesPath
        self.isSettingsPresented = isSettingsPresented
        self.isWorkoutCoverPresented = isWorkoutCoverPresented
        self.isWorkoutMinimised = isWorkoutMinimised
    }

    // MARK: Tabs

    /// Selects a tab. Selecting the already-selected tab pops it to its root (standard iOS behaviour).
    public func select(_ tab: AppTab) {
        if tab == selectedTab {
            popToRoot(tab)
        } else {
            selectedTab = tab
        }
    }

    // MARK: Stacks

    public func push(_ route: HistoryRoute) { historyPath.append(route) }
    public func push(_ route: WorkoutRoute) { workoutPath.append(route) }
    public func push(_ route: ExercisesRoute) { exercisesPath.append(route) }

    public func popToRoot(_ tab: AppTab) {
        switch tab {
        case .history: historyPath.removeAll()
        case .workout: workoutPath.removeAll()
        case .exercises: exercisesPath.removeAll()
        }
    }

    // MARK: Deep links

    /// Opens a past workout's detail: History tab, stack reset to it.
    public func openWorkout(_ id: UUID) {
        selectedTab = .history
        historyPath = [.workout(id)]
    }

    /// Whether `url` is the link the Live Activity (banner and Dynamic Island) opens: `workouts://workout`.
    public static func isActiveWorkoutLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "workouts" && url.host(percentEncoded: false)?.lowercased() == "workout"
    }

    /// Brings the running workout forward from outside the app (the Live Activity): Workout tab, cover presented. The
    /// caller closes the root sheets (Settings, the finish summary) first, since a cover cannot present over a sheet. A
    /// tab's own sheet is left alone (it may hold typed input); if it blocks the cover, the resume ring covers the gap.
    public func openActiveWorkout() {
        // An open editor is never closed by the request: wait for it to go away (Save or Cancel).
        guard !isEditorCoverOnScreen else {
            isWorkoutOpenPending = true
            return
        }
        isWorkoutOpenPending = false
        selectedTab = .workout
        presentWorkout()
    }

    /// Records that an editor cover appeared or disappeared; when it disappears, a deferred open request is fulfilled.
    public func setEditorCoverOnScreen(_ onScreen: Bool) {
        isEditorCoverOnScreen = onScreen
        if !onScreen, isWorkoutOpenPending { openActiveWorkout() }
    }

    // MARK: Settings

    public func openSettings() { isSettingsPresented = true }

    // MARK: Active workout

    /// Presents the active workout's cover: used on start, by the resume control, and to restore on relaunch.
    public func presentWorkout() {
        isWorkoutCoverPresented = true
        isWorkoutMinimised = false
    }

    /// Minimise: dismisses the cover while the workout keeps running. A no-op when the cover is not showing.
    public func minimiseWorkout() {
        guard isWorkoutCoverPresented else { return }
        isWorkoutCoverPresented = false
        isWorkoutMinimised = true
    }

    /// Finish or Discard: no workout is running any more, so there is neither a cover nor a resume control.
    public func endWorkout() {
        isWorkoutOpenPending = false
        isWorkoutCoverPresented = false
        isWorkoutMinimised = false
    }
}
