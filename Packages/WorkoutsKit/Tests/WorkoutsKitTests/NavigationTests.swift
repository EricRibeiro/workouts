import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct NavigationTests {
    private let a = UUID()
    private let b = UUID()

    @Test func tabsAreInEricsOrderAndWorkoutIsDefault() {
        #expect(AppTab.main == [.history, .workout, .exercises])
        #expect(AppTab.default == .workout)
        let nav = AppNavigation()
        #expect(nav.selectedTab == .workout)
        #expect(nav.historyPath.isEmpty && nav.workoutPath.isEmpty && nav.exercisesPath.isEmpty)
        #expect(!nav.isSettingsPresented)
        #expect(!nav.isWorkoutCoverPresented)
        #expect(!nav.isWorkoutMinimised)
    }

    @Test func selectChangesTabAndKeepsStacks() {
        let nav = AppNavigation()
        nav.push(WorkoutRoute.template(a))
        nav.select(.history)
        #expect(nav.selectedTab == .history)
        #expect(nav.workoutPath == [.template(a)])
    }

    @Test func stacksAreIndependentPerTab() {
        let nav = AppNavigation()
        nav.push(HistoryRoute.workout(a))
        nav.push(HistoryRoute.editWorkout(a))
        nav.push(WorkoutRoute.editTemplate(b))
        nav.push(ExercisesRoute.exercise(b))
        #expect(nav.historyPath == [.workout(a), .editWorkout(a)])
        #expect(nav.workoutPath == [.editTemplate(b)])
        #expect(nav.exercisesPath == [.exercise(b)])
    }

    @Test func popToRootClearsOnlyThatTab() {
        let nav = AppNavigation()
        nav.push(HistoryRoute.workout(a))
        nav.push(WorkoutRoute.template(a))
        nav.push(ExercisesRoute.exercise(a))
        nav.popToRoot(.workout)
        #expect(nav.workoutPath.isEmpty)
        #expect(nav.historyPath == [.workout(a)])
        #expect(nav.exercisesPath == [.exercise(a)])
        nav.popToRoot(.history)
        nav.popToRoot(.exercises)
        #expect(nav.historyPath.isEmpty && nav.exercisesPath.isEmpty)
    }

    @Test func reselectingTheSelectedTabPopsItToRoot() {
        let nav = AppNavigation()
        nav.push(WorkoutRoute.template(a))
        nav.push(HistoryRoute.workout(b))
        nav.select(.workout)
        #expect(nav.selectedTab == .workout)
        #expect(nav.workoutPath.isEmpty)
        #expect(nav.historyPath == [.workout(b)])
    }

    @Test func openWorkoutSelectsHistoryAndResetsItsStack() {
        let nav = AppNavigation(historyPath: [.editWorkout(b)])
        nav.openWorkout(a)
        #expect(nav.selectedTab == .history)
        #expect(nav.historyPath == [.workout(a)])
    }

    @Test func settingsOpensAndCloses() {
        let nav = AppNavigation()
        nav.openSettings()
        #expect(nav.isSettingsPresented)
        nav.isSettingsPresented = false
        #expect(!nav.isSettingsPresented)
    }

    @Test func workoutCoverPresentMinimiseRestore() {
        let nav = AppNavigation()
        nav.presentWorkout()
        #expect(nav.isWorkoutCoverPresented && !nav.isWorkoutMinimised)

        nav.minimiseWorkout()
        #expect(!nav.isWorkoutCoverPresented && nav.isWorkoutMinimised)

        // A running workout survives any tab change.
        nav.select(.exercises)
        #expect(nav.isWorkoutMinimised)

        nav.presentWorkout()
        #expect(nav.isWorkoutCoverPresented && !nav.isWorkoutMinimised)
    }

    @Test func minimiseWithoutACoverDoesNothing() {
        let nav = AppNavigation()
        nav.minimiseWorkout()
        #expect(!nav.isWorkoutCoverPresented && !nav.isWorkoutMinimised)
    }

    @Test func endWorkoutClearsCoverAndMinimisedState() {
        let nav = AppNavigation()
        nav.presentWorkout()
        nav.endWorkout()
        #expect(!nav.isWorkoutCoverPresented && !nav.isWorkoutMinimised)

        nav.presentWorkout()
        nav.minimiseWorkout()
        nav.endWorkout()
        #expect(!nav.isWorkoutCoverPresented && !nav.isWorkoutMinimised)
    }

    @Test func routesRoundTripThroughJSON() throws {
        let history: [HistoryRoute] = [.workout(a), .editWorkout(b)]
        let workout: [WorkoutRoute] = [.template(a), .editTemplate(b)]
        let exercises: [ExercisesRoute] = [.exercise(a)]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        #expect(try decoder.decode([HistoryRoute].self, from: encoder.encode(history)) == history)
        #expect(try decoder.decode([WorkoutRoute].self, from: encoder.encode(workout)) == workout)
        #expect(try decoder.decode([ExercisesRoute].self, from: encoder.encode(exercises)) == exercises)
    }
}
