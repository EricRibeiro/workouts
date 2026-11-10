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
    /// A Live Activity or notification tap that arrived while a root sheet (Settings, the finish summary) was up: the
    /// cover opens once the sheet is gone.
    @State private var openWorkoutAfterSheet = false
    @Environment(\.modelContext) private var context
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    /// Optional so previews without the services still build; a notification-body tap arrives through it.
    @Environment(WorkoutLinkRouter.self) private var links: WorkoutLinkRouter?
    @Environment(SaveErrors.self) private var saveErrors: SaveErrors?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    /// Optional so previews without the services still build; nil behaves like "videos not downloaded".
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @Environment(ExerciseStore.self) private var exerciseStore: ExerciseStore?
    /// Optional so previews without the services still build; nil behaves like "no Health here".
    @Environment(HealthEnrichmentService.self) private var health: HealthEnrichmentService?
    /// Whether the cover was open when the app last changed it: per device, so a relaunch can reopen it (task 2.7). A
    /// minimised workout relaunches as only the resume ring.
    @AppStorage("workoutCoverWasOpen") private var coverWasOpen = false

    /// A presentation keeps its last override when the preference goes back to nil (System), so it gets the root's resolved scheme.
    private var presentationScheme: ColorScheme {
        settings?.appearance.colorScheme ?? colorScheme
    }

    var body: some View {
        TabView(selection: Binding(get: { navigation.selectedTab }, set: { navigation.select($0) })) {
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView(path: $navigation.historyPath)
            }
            .accessibilityIdentifier("tab.history")

            Tab("Workout", systemImage: "dumbbell", value: AppTab.workout) {
                WorkoutView(presentWorkout: { navigation.presentWorkout() })
            }
            .accessibilityIdentifier("tab.workout")

            Tab("Exercises", systemImage: "figure.strengthtraining.traditional", value: AppTab.exercises) {
                ExercisesView()
            }
            .accessibilityIdentifier("tab.exercises")
        }
        .environment(navigation)
        // The one rest watcher while the cover is closed (the cover hosts its own): it outlives the resume ring, which is
        // gone on a pushed screen. Exactly one is active at a time, so the haptic never doubles.
        .restExpiryWatcher(isActive: !navigation.isWorkoutCoverOnScreen)
        #if DEBUG
            .restStateProbe()
            .interfaceStyleProbe()
            .healthLookupProbe()
        #endif
        // The scrolling lists (History, Exercises) let the tab bar collapse; the Workout tab keeps it (DECISIONS).
        .tabBarMinimizeBehavior(navigation.selectedTab == .workout ? .never : .onScrollDown)
        .onOpenURL { url in
            if AppNavigation.isActiveWorkoutLink(url) { openWorkoutLink() }
        }
        // The rest notification's body: the same path as the Live Activity link (also a request made before this appeared).
        .onChange(of: links?.isPending ?? false, initial: true) { _, pending in
            if pending, links?.consume() == true { openWorkoutLink() }
        }
        .sheet(
            isPresented: $navigation.isSettingsPresented,
            onDismiss: openPendingWorkout
        ) {
            SettingsView()
                .preferredColorScheme(presentationScheme)
                .presentationPlacement(.center)
        }
        .sheet(
            item: $finishSummary,
            onDismiss: {
                askToUpdateTemplate()
                openPendingWorkout()
            }
        ) { item in
            FinishSummaryView(summary: item.summary)
                .preferredColorScheme(presentationScheme)
                .presentationPlacement(.center)
        }
        .templateUpdateDialog($templateUpdate, apply: applyTemplateUpdate)
        .fullScreenCover(
            isPresented: $navigation.isWorkoutCoverPresented,
            onDismiss: {
                finishSummary = pendingSummary
                // No summary sheet to follow (it could not be built): the template question comes now.
                if pendingSummary == nil { askToUpdateTemplate() }
                pendingSummary = nil
            }
        ) {
            ActiveWorkoutCover(
                minimise: { navigation.minimiseWorkout() },
                onFinished: { summary in
                    workoutSaved(id: summary.workoutID, summary: summary)
                },
                onDiscarded: { navigation.endWorkout() },
                onSavedWithoutSummary: { id in workoutSaved(id: id, summary: nil) }
            )
            .preferredColorScheme(presentationScheme)
            // What is actually showing, as opposed to requested: the resume ring keys off this.
            .onAppear { navigation.isWorkoutCoverOnScreen = true }
            .onDisappear { navigation.isWorkoutCoverOnScreen = false }
        }
        // The covers (the workout, the editors) host their own alert; this one stands down while one is up, since a
        // presenter cannot show a second.
        .saveErrorAlert(isEnabled: !navigation.isWorkoutCoverPresented && (saveErrors?.hostDepth ?? 0) == 0)
        .onChange(of: navigation.isWorkoutCoverPresented) { _, isPresented in
            coverWasOpen = isPresented
        }
        .onAppear(perform: restoreCover)
        // Coming back to the foreground is when a Watch workout recorded meanwhile can be picked up (when the person opted in).
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Inactive comes before background and before the app can be killed: write what was typed in the focused field.
            if phase != .active { commitTypedValues() }
            guard phase == .active else { return }
            // "Download all videos" survives a kill or a cellular start: pick it up again (cached videos are skipped).
            if let settings, let exerciseStore {
                BulkVideoDownload.shared.resumeIfEnabled(
                    settings: settings,
                    catalog: exerciseStore.catalog,
                    scheme: colorScheme == .dark ? .dark : .light
                )
            }
            guard let health else { return }
            Task { await health.appBecameActive(context: context) }
        }
    }
}

extension RootView {
    /// `workouts://workout` (the Live Activity banner or Dynamic Island) and the rest notification's body: the running
    /// workout's cover on the Workout tab. Does nothing without a running workout.
    private func openWorkoutLink() {
        guard engine?.workout != nil else { return }
        // A cover cannot present over a sheet: close the root sheet, then open the cover from its onDismiss.
        if navigation.isSettingsPresented || finishSummary != nil {
            openWorkoutAfterSheet = true
            navigation.isSettingsPresented = false
            finishSummary = nil
        } else {
            navigation.openActiveWorkout()
        }
    }

    /// A finished workout is saved: Health picks it up, the summary (when it could be built) is held until the cover has
    /// closed, the "Update Template?" question waits for the summary to go, and the workout ends.
    private func workoutSaved(id: UUID?, summary: FinishSummary?) {
        health?.workoutFinished(context: context)
        pendingSummary = summary.map(FinishSummaryItem.init(summary:))
        summaryWorkoutID = id
        navigation.endWorkout()
    }

    private func openPendingWorkout() {
        guard openWorkoutAfterSheet else { return }
        openWorkoutAfterSheet = false
        guard engine?.workout != nil else { return }
        navigation.openActiveWorkout()
    }

    /// Saves the set values typed since the last save (the engine's `setValues` does not save per keystroke).
    private func commitTypedValues() {
        do {
            try engine?.commitEdits()
        } catch {
            saveErrors?.report(error)
        }
    }

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
