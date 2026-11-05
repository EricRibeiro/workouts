//
//  SettingsView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WorkoutsKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    /// The app's one `SettingsStore` (injected by `WorkoutsApp`): every change writes straight back through it, and the
    /// rest of the app sees it at once. `@Observable`, so the controls bind to it directly.
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    /// Optional so the screen still builds where no store is injected; Import then skips the library check.
    @Environment(ExerciseStore.self) private var exerciseStore: ExerciseStore?
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    /// Bumped after an import so the History, Exercises and Workout caches re-derive (an import can update an older workout).
    @Environment(StoreGeneration.self) private var generation: StoreGeneration?
    /// Optional like the store above; the Apple Fitness section shows only where Health is available.
    @Environment(HealthEnrichmentService.self) private var health: HealthEnrichmentService?

    private let download = BulkVideoDownload.shared
    @State private var isPickingFile = false
    @State private var isImporting = false
    @State private var outcome: TransferOutcome?
    @State private var isTurningOffFitness = false

    /// What the result alert shows after an import.
    private struct TransferOutcome {
        let title: String
        let message: String
    }

    private var bound: Bindable<SettingsStore> { Bindable(settings) }

    /// Seconds offered by the rest menu (`history.md` section 8); 0 is shown as "Off".
    private static let restOptions = [0, 30, 45, 60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        NavigationStack {
            Form {
                unitsAndRecords
                workout
                media
                appleFitness
                iCloud
                data
                #if DEBUG
                    DebugSection()
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityLabel("Done")
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
        .accessibilityIdentifier("screen.settings")
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): runImport(url)
            case .failure(let error):
                outcome = TransferOutcome(title: "Could Not Import", message: DataTransfer.message(for: error))
            }
        }
        // An alert, not a dialog: it is raised from a toggle, and a dialog's popover arrow would point at nothing sensible.
        .alert("Turn Off Apple Fitness?", isPresented: $isTurningOffFitness) {
            Button("Keep Fitness Data") { turnOffFitness(removeData: false) }
                .accessibilityIdentifier("settings.health.keep")
            Button("Remove Fitness Data", role: .destructive) { turnOffFitness(removeData: true) }
                .accessibilityIdentifier("settings.health.remove")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("settings.health.cancel")
        } message: {
            Text(
                "Workouts stops reading Fitness workouts. Keep the calories and heart rate already added, or remove them?"
            )
        }
        .alert(
            outcome?.title ?? "",
            isPresented: Binding(get: { outcome != nil }, set: { if !$0 { outcome = nil } }),
            presenting: outcome
        ) { _ in
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("settings.transferOK")
        } message: { outcome in
            Text(outcome.message)
        }
    }

    private var data: some View {
        Section {
            Button("Import…", systemImage: "square.and.arrow.down") { isPickingFile = true }
                .disabled(isImporting)
                .accessibilityLabel("Import")
                .accessibilityIdentifier("settings.import")
            ShareLink(
                item: ExportArchive(container: modelContext.container, catalog: exerciseStore?.catalog),
                preview: SharePreview(WorkoutsJSON.exportFileName(for: Date()))
            ) {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Export")
            .accessibilityIdentifier("settings.export")
        } header: {
            Text("Data")
        } footer: {
            Text(
                "Export saves your workouts, templates and custom exercises as one JSON file. Import reads such a file; rows already here are left alone unless the file's copy is newer."
            )
        }
    }

    private func runImport(_ url: URL) {
        isImporting = true
        let context = modelContext
        let catalog = exerciseStore?.catalog
        Task {
            defer { isImporting = false }
            do {
                let document = try await DataTransfer.readDocument(at: url)
                let report = try DataTransfer.apply(document, to: context, catalog: catalog)
                generation?.bump()
                // Imported custom exercises must reach the pickers and detail screens.
                exerciseStore?.setCustom(try modelContext.fetch(FetchDescriptor<Exercise>()))
                // A legitimately imported unfinished workout (no other running) shows at once, not after relaunch.
                if engine?.workout == nil { try engine?.resume() }
                outcome = TransferOutcome(title: report.headline, message: report.summary)
                // Imported history never got Fitness data when it was recorded; look it up once (no-op while off).
                if let health { Task { await health.backfill(context: context) } }
            } catch {
                outcome = TransferOutcome(title: "Could Not Import", message: DataTransfer.message(for: error))
            }
        }
    }

    private var unitsAndRecords: some View {
        Section {
            VStack(alignment: .leading) {
                Text("Weight unit")
                Picker("Weight unit", selection: bound.defaultUnit) {
                    ForEach(WeightUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Weight unit")
                .accessibilityIdentifier("settings.defaultUnit")
            }
            VStack(alignment: .leading) {
                Text("Estimated 1RM formula")
                Picker("Estimated 1RM formula", selection: bound.e1rmFormula) {
                    Text("Epley").tag(E1RMFormula.epley)
                    Text("Brzycki").tag(E1RMFormula.brzycki)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Estimated 1RM formula")
                .accessibilityIdentifier("settings.e1rmFormula")
            }
        } header: {
            Text("Units & Records")
        } footer: {
            // One footer for both rows: a Section has a single footer. The spec's two footers, in row order.
            Text("Logged weights stay as entered. Brzycki reads higher at low reps.")
        }
    }

    private var workout: some View {
        Section("Workout") {
            Picker("Default rest timer", selection: bound.defaultRestSeconds) {
                ForEach(restChoices, id: \.self) { seconds in
                    Text(seconds == 0 ? "Off" : ElapsedFormat.string(seconds: seconds)).tag(seconds)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("settings.defaultRestSeconds")

            Stepper(value: bound.weeklyGoal, in: 1...14) {
                LabeledContent("Weekly goal", value: "\(settings.weeklyGoal)")
            }
            .accessibilityLabel("Weekly goal")
            .accessibilityValue("\(settings.weeklyGoal) workouts per week")
            .accessibilityIdentifier("settings.weeklyGoal")

            Toggle("Keep screen on during a workout", isOn: bound.keepScreenOn)
                .accessibilityLabel("Keep screen on during a workout")
                .accessibilityIdentifier("settings.keepScreenOn")
        }
    }

    /// The built-in options, plus the current value when it is off-list (an imported or earlier value stays selectable).
    private var restChoices: [Int] {
        let current = settings.defaultRestSeconds
        return Self.restOptions.contains(current) ? Self.restOptions : (Self.restOptions + [current]).sorted()
    }

    private var media: some View {
        Section {
            Toggle("Download all videos", isOn: bound.downloadAllVideos)
                .accessibilityLabel("Download all videos")
                .accessibilityIdentifier("settings.downloadAllVideos")
            if let progress = download.progress {
                VStack(alignment: .leading) {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    Text("\(progress.done) of \(progress.total) videos")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Video download progress")
                .accessibilityValue("\(progress.done) of \(progress.total) videos")
                .accessibilityIdentifier("settings.downloadProgress")
            }
        } header: {
            Text("Media")
        } footer: {
            Text("Downloads over Wi-Fi only.")
        }
        .onChange(of: settings.downloadAllVideos, initial: true) { _, isOn in
            if isOn { startDownload() } else { download.cancel() }
        }
    }

    /// Prefetches the library's videos for the current colour scheme; videos already cached are skipped at once.
    private func startDownload() {
        guard let catalog = exerciseStore?.catalog else { return }
        let ids = catalog.exercises.filter(\.hasVideos).map(\.sourceId)
        download.start(sourceIDs: ids, scheme: colorScheme == .dark ? .dark : .light)
    }

    @ViewBuilder
    private var appleFitness: some View {
        if let health, health.isAvailable {
            Section {
                Toggle("Read Apple Fitness Workouts", isOn: fitnessBinding(health))
                    .accessibilityLabel("Read Apple Fitness Workouts")
                    .accessibilityIdentifier("settings.health.enabled")
            } header: {
                Text("Apple Fitness")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "Reads calories and heart rate from the Apple Fitness strength workout you record alongside each session. Workouts never writes to Health."
                    )
                    if let progress = health.backfillProgress {
                        Text("Adding Fitness data… \(progress.done) of \(progress.total)")
                            .accessibilityIdentifier("settings.health.progress")
                    }
                }
            }
        }
    }

    /// On turns the setting on and shows the Health sheet (then looks up what is waiting). Off does not change anything
    /// yet: it asks whether to keep the data already added, and Cancel leaves the toggle on.
    private func fitnessBinding(_ health: HealthEnrichmentService) -> Binding<Bool> {
        Binding(
            get: { settings.healthEnrichmentEnabled },
            set: { isOn in
                if isOn {
                    settings.healthEnrichmentEnabled = true
                    Task { await health.requestAuthorization(context: modelContext) }
                } else {
                    isTurningOffFitness = true
                }
            }
        )
    }

    private func turnOffFitness(removeData: Bool) {
        guard let health else { return }
        Task {
            do {
                try await health.turnOff(remove: removeData, context: modelContext)
            } catch {
                outcome = TransferOutcome(
                    title: "Could Not Remove Fitness Data",
                    message: error.localizedDescription
                )
            }
        }
    }

    private var iCloud: some View {
        Section {
            // No iCloud entitlement and a local-only container yet, so there is no account status to read.
            LabeledContent("Status", value: "Not available yet")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("iCloud status")
                .accessibilityValue("Not available yet")
                .accessibilityIdentifier("settings.iCloudStatus")
        } header: {
            Text("iCloud")
        } footer: {
            Text("iCloud sync arrives in a later version.")
        }
    }
}

#if DEBUG
    /// Debug-only tools. "Load sample data" seeds the environment's model context with `SampleData`.
    private struct DebugSection: View {
        @Environment(\.modelContext) private var modelContext
        @State private var message: String?

        var body: some View {
            Section("Debug") {
                Button("Load sample data", systemImage: "square.and.arrow.down") { loadSampleData() }
                    .accessibilityLabel("Load sample data")
                    .accessibilityIdentifier("settings.loadSampleData")
            }
            .alert(
                "Sample data",
                isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }

        private func loadSampleData() {
            do {
                let catalog = try LibraryCatalog.bundled(in: .main)
                try SampleData.seed(into: modelContext, catalog: catalog)
                message = "Loaded 3 templates and 50 workouts."
            } catch {
                message = "Could not load sample data: \(error.localizedDescription)"
            }
        }
    }
#endif

private struct SettingsPreview: View {
    var body: some View {
        if let container = try? ModelContainer.preview(catalog: LibraryCatalog.bundled(in: .main)) {
            SettingsView().modelContainer(container).environment(SettingsStore())
        } else {
            SettingsView().environment(SettingsStore())
        }
    }
}

#Preview("Large") {
    SettingsPreview().dynamicTypeSize(.large)
}

#Preview("Accessibility 3") {
    SettingsPreview().dynamicTypeSize(.accessibility3)
}
