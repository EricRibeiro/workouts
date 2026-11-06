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

    /// The past-workout editor on the History stack holds unsaved edits. Kept in sync by the editor (its draft is view
    /// state); only meaningful while `historyPath` holds an `.editWorkout`, so a stale `true` after the editor is gone
    /// does nothing. While protected, nothing may replace or pop the History stack: Back is hidden, so the editor's own
    /// Cancel confirmation is the only way out.
    public var isHistoryEditorDirty: Bool

    /// Whether unsaved past-workout edits are on screen and the History stack must stay as it is.
    public var isHistoryStackProtected: Bool {
        isHistoryEditorDirty && historyPath.contains { if case .editWorkout = $0 { true } else { false } }
    }

    /// The Settings `Form` sheet, opened from the Workout tab's gear.
    public var isSettingsPresented: Bool

    /// The active workout's `fullScreenCover` on the root `TabView`, not tied to any tab.
    public var isWorkoutCoverPresented: Bool

    /// Whether the cover is actually on screen (set from its `onAppear`/`onDisappear`). `isWorkoutCoverPresented` is only
    /// the request: a cover cannot present while a sheet is up, and then the request stays true with nothing showing. The
    /// resume ring keys off this, so the person always has the cover or the ring.
    public var isWorkoutCoverOnScreen = false

    /// A workout is running but its cover is dismissed (DECISIONS: Minimise "dismisses the cover; the resume
    /// control restores it; a running workout survives any tab change"). Drives the ring `ToolbarItem`.
    public private(set) var isWorkoutMinimised: Bool

    public init(
        selectedTab: AppTab = .default,
        historyPath: [HistoryRoute] = [],
        workoutPath: [WorkoutRoute] = [],
        exercisesPath: [ExercisesRoute] = [],
        isHistoryEditorDirty: Bool = false,
        isSettingsPresented: Bool = false,
        isWorkoutCoverPresented: Bool = false,
        isWorkoutMinimised: Bool = false
    ) {
        self.selectedTab = selectedTab
        self.historyPath = historyPath
        self.workoutPath = workoutPath
        self.exercisesPath = exercisesPath
        self.isHistoryEditorDirty = isHistoryEditorDirty
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

    /// Writes the History stack from the view (the `NavigationStack` path binding, which the system also writes when a
    /// tab is reselected). While unsaved editor edits are on screen a shrinking write is ignored, so no system pop can
    /// destroy them; pushes go through.
    public func setHistoryPath(_ newPath: [HistoryRoute]) {
        if isHistoryStackProtected && newPath.count < historyPath.count { return }
        historyPath = newPath
    }

    public func popToRoot(_ tab: AppTab) {
        switch tab {
        case .history:
            guard !isHistoryStackProtected else { return }
            historyPath.removeAll()
        case .workout: workoutPath.removeAll()
        case .exercises: exercisesPath.removeAll()
        }
    }

    // MARK: Deep links

    /// Opens a past workout's detail: History tab, stack reset to it. With unsaved editor edits on the History stack it
    /// only switches to the tab, leaving the stack (and the editor) alone so the person can save or cancel first.
    public func openWorkout(_ id: UUID) {
        selectedTab = .history
        guard !isHistoryStackProtected else { return }
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
        selectedTab = .workout
        presentWorkout()
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
        isWorkoutCoverPresented = false
        isWorkoutMinimised = false
    }
}
