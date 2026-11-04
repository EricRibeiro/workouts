//
//  RootView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The app shell: three tabs (sidebar-adaptable), the sidebar-only template sections and the Settings sheet.
struct RootView: View {
    @State private var navigation = AppNavigation()
    /// The finished workout's numbers, held until the cover has closed.
    @State private var pendingSummary: FinishSummaryItem?
    /// The summary sheet's item; presented from here (not the cover) once the cover is gone.
    @State private var finishSummary: FinishSummaryItem?
    /// The finished workout behind the pending summary, for the "Update Template?" question once the summary is gone.
    @State private var summaryWorkoutID: UUID?
    @State private var templateUpdate: TemplateUpdatePrompt?
    /// The sidebar's "New Template" asked for the editor; the Workout tab consumes it.
    @State private var newTemplate: NewTemplateRequest?
    @Query(sort: [SortDescriptor(\TemplateFolder.position), SortDescriptor(\TemplateFolder.name)])
    private var folders: [TemplateFolder]
    @Query private var templates: [Template]
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                    presentWorkout: { navigation.presentWorkout() },
                    newTemplate: $newTemplate
                )
            }
            .accessibilityIdentifier("tab.workout")

            Tab("Exercises", systemImage: "figure.strengthtraining.traditional", value: AppTab.exercises) {
                ExercisesView()
            }
            .accessibilityIdentifier("tab.exercises")

            // The templates, by folder, for the sidebar only (see `templateSections`).
            templateSections
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(navigation)
        // `defaultAdaptableTabBarPlacement` is iPadOS-only; on iPhone (the Duo) the style resolves statically, so only
        // `defaultTabBarPlacement` gives the open Duo its real leading sidebar (see DECISIONS "Navigation and layout").
        .defaultTabBarPlacement(.sidebar)
        // The scrolling lists (History, Exercises) let the tab bar collapse; the Workout tab keeps it (DECISIONS).
        .tabBarMinimizeBehavior(navigation.selectedTab == .workout ? .never : .onScrollDown)
        .tabViewSidebarBottomBar {
            ResumeCard(engine: engine, navigation: navigation, errors: saveErrors)
            if horizontalSizeClass == .regular {
                Button("Settings", systemImage: "gearshape") { navigation.openSettings() }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("sidebar.settings")
            }
        }
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
        .onChange(of: horizontalSizeClass) { _, sizeClass in
            // The sidebar went away (the Duo closed): so did the template tabs.
            if sizeClass != .regular, case .template = navigation.selectedTab { navigation.select(.workout) }
        }
        .onChange(of: Set(templates.map(\.id))) { _, ids in
            // The selected template went away (deleted here or by sync): its tab is gone, so fall back to Workout.
            if case .template(let id) = navigation.selectedTab, !ids.contains(id) {
                navigation.select(.workout)
            }
        }
        .onAppear(perform: restoreCover)
    }

    /// The template sections, one `TabSection` per folder (and Unfiled), their tabs `.sidebarOnly`. In 27.2 `.sidebarOnly`
    /// (and `defaultVisibility(.hidden, for: .tabBar)`) still leaks these tabs into the bar, and compact width means there
    /// is no sidebar anyway (the closed Duo), so the sections are built only at regular width, where the sidebar exists
    /// (expanded when the Duo is open wide, behind its toggle when open tall). The compact bar is then the three main tabs.
    @TabContentBuilder<AppTab>
    private var templateSections: some TabContent<AppTab> {
        if horizontalSizeClass == .regular {
            ForEach(FolderOperations.ordered(folders)) { folder in
                TabSection(folder.name) {
                    ForEach(FolderOperations.orderedTemplates(templates.filter { $0.folder?.id == folder.id })) {
                        templateTab($0)
                    }
                }
                .sectionActions { newTemplateButton(in: folder.id) }
                .tabPlacement(.sidebarOnly)
            }
            if !unfiledTemplates.isEmpty {
                TabSection("Unfiled") {
                    ForEach(unfiledTemplates) { templateTab($0) }
                }
                .sectionActions { newTemplateButton(in: nil) }
                .tabPlacement(.sidebarOnly)
            }
        }
    }

    private var unfiledTemplates: [Template] {
        FolderOperations.orderedTemplates(templates.filter { $0.folder == nil })
    }

    @TabContentBuilder<AppTab>
    private func templateTab(_ template: Template) -> some TabContent<AppTab> {
        Tab(template.name, systemImage: "list.bullet.rectangle", value: AppTab.template(template.id)) {
            TemplateTab(template: template, presentWorkout: { navigation.presentWorkout() })
        }
        .accessibilityIdentifier("sidebar.template.\(template.id.uuidString)")
        .tabPlacement(.sidebarOnly)
        .defaultVisibility(.hidden, for: .tabBar)
    }

    /// A section's "New Template": selects the Workout tab and asks it to push the editor, creating in `folderID`.
    private func newTemplateButton(in folderID: UUID?) -> some View {
        Button("New Template", systemImage: "square.and.pencil") {
            navigation.select(.workout)
            newTemplate = NewTemplateRequest(folderID: folderID)
        }
        .accessibilityLabel("New Template")
        .accessibilityIdentifier(
            folderID.map { "sidebar.newTemplate.\($0.uuidString)" } ?? "sidebar.newTemplate.unfiled"
        )
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
    /// only the resume ring. Debug: `-openWorkoutCover` opens it; UI tests (`-uiTesting`, an in-memory store) ignore the
    /// stored flag so one run never leaks into the next.
    private func restoreCover() {
        var reopen = coverWasOpen && engine?.workout != nil
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-uiTesting") { reopen = false }
            if arguments.contains("-openWorkoutCover") { reopen = true }
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
