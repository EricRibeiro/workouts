//
//  RootView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The app shell: three tabs in the system tab bar (the trailing strip on the Duo's closed display, JC52: no sidebar) and
/// the Settings sheet.
struct RootView: View {
    @State private var navigation = AppNavigation()
    /// The finished workout's numbers, held until the cover has closed.
    @State private var pendingSummary: FinishSummaryItem?
    /// The summary sheet's item; presented from here (not the cover) once the cover is gone.
    @State private var finishSummary: FinishSummaryItem?
    /// The finished workout behind the pending summary, for the "Update Template?" question once the summary is gone.
    @State private var summaryWorkoutID: UUID?
    @State private var templateUpdate: TemplateUpdatePrompt?
    @Environment(\.modelContext) private var context
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    @Environment(SaveErrors.self) private var saveErrors: SaveErrors?
    /// Whether the cover was open when the app last changed it: per device, so a relaunch can reopen it (task 2.7). A
    /// minimised workout relaunches as only the resume ring.
    @AppStorage("workoutCoverWasOpen") private var coverWasOpen = false

    var body: some View {
        TabView(selection: Binding(get: { navigation.selectedTab }, set: { navigation.select($0) })) {
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView(path: $navigation.historyPath)
            }
            .accessibilityIdentifier("tab.history")

            Tab("Workout", systemImage: "dumbbell", value: AppTab.workout) {
                WorkoutView(
                    showSettings: { navigation.openSettings() },
                    presentWorkout: { navigation.presentWorkout() }
                )
            }
            .accessibilityIdentifier("tab.workout")

            Tab("Exercises", systemImage: "figure.strengthtraining.traditional", value: AppTab.exercises) {
                ExercisesView()
            }
            .accessibilityIdentifier("tab.exercises")
        }
        .environment(navigation)
        // The scrolling lists (History, Exercises) let the tab bar collapse; the Workout tab keeps it (DECISIONS).
        .tabBarMinimizeBehavior(navigation.selectedTab == .workout ? .never : .onScrollDown)
        .sheet(isPresented: $navigation.isSettingsPresented) {
            SettingsView()
                .presentationPlacement(.center)
        }
        .sheet(item: $finishSummary, onDismiss: askToUpdateTemplate) { item in
            FinishSummaryView(summary: item.summary)
                .presentationPlacement(.center)
        }
        .templateUpdateDialog($templateUpdate, apply: applyTemplateUpdate)
        .fullScreenCover(
            isPresented: $navigation.isWorkoutCoverPresented,
            onDismiss: {
                finishSummary = pendingSummary
                pendingSummary = nil
            }
        ) {
            ActiveWorkoutCover(
                minimise: { navigation.minimiseWorkout() },
                onFinished: { summary in
                    pendingSummary = FinishSummaryItem(summary: summary)
                    summaryWorkoutID = summary.workoutID
                    navigation.endWorkout()
                },
                onDiscarded: { navigation.endWorkout() }
            )
        }
        // The cover hosts its own alert; this one stands down while it is up, since a presenter cannot show a second.
        .saveErrorAlert(isEnabled: !navigation.isWorkoutCoverPresented)
        .onChange(of: navigation.isWorkoutCoverPresented) { _, isPresented in
            coverWasOpen = isPresented
        }
        .onAppear(perform: restoreCover)
    }
}

extension RootView {
    /// After the summary sheet is gone: if the finished workout came from a template it no longer matches, ask whether to
    /// update the template. Skipped when the template was deleted meanwhile (`Workout.template` is then nil).
    private func askToUpdateTemplate() {
        guard let id = summaryWorkoutID else { return }
        summaryWorkoutID = nil
        do {
            guard let workout = try finishedWorkout(id), let template = workout.template else { return }
            let kind = TemplateUpdate.diff(template: template, workout: workout)
            guard kind != .none else { return }
            templateUpdate = TemplateUpdatePrompt(workoutID: id, templateName: template.name, kind: kind)
        } catch {
            saveErrors?.report(error)
        }
    }

    private func applyTemplateUpdate(_ choice: TemplateUpdate.Choice, _ prompt: TemplateUpdatePrompt) {
        do {
            guard let workout = try finishedWorkout(prompt.workoutID), let template = workout.template else { return }
            try TemplateUpdate.apply(choice, template: template, workout: workout, in: context)
        } catch {
            saveErrors?.report(error)
        }
    }

    private func finishedWorkout(_ id: UUID) throws -> Workout? {
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Launch: reopen the cover if it was open when the app quit and a workout survived; a minimised workout comes back as
    /// only the resume ring. Debug: `-openWorkoutCover` opens it, `-selectTab <name>` picks the tab; UI tests (`-uiTesting`, an in-memory store) ignore the
    /// stored flag so one run never leaks into the next.
    private func restoreCover() {
        var reopen = coverWasOpen && engine?.workout != nil
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-uiTesting") { reopen = false }
            if arguments.contains("-openWorkoutCover") { reopen = true }
            // `-selectTab history|exercises`: opens that tab at launch (screenshots, where nothing can tap).
            if let flag = arguments.firstIndex(of: "-selectTab"), arguments.indices.contains(flag + 1) {
                switch arguments[flag + 1] {
                case "history": navigation.select(.history)
                case "exercises": navigation.select(.exercises)
                default: break
                }
            }
        #endif
        if reopen {
            navigation.presentWorkout()
        } else if coverWasOpen {
            coverWasOpen = false
        }
    }
}

#Preview {
    RootView()
}
