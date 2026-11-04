//
//  SettingsView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    /// The app's one `SettingsStore` (injected by `WorkoutsApp`): every change writes straight back through it, and the
    /// rest of the app sees it at once. `@Observable`, so the controls bind to it directly.
    @Environment(SettingsStore.self) private var settings

    private var bound: Bindable<SettingsStore> { Bindable(settings) }

    /// Seconds offered by the rest menu (`history.md` section 8); 0 is shown as "Off".
    private static let restOptions = [0, 30, 45, 60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        NavigationStack {
            Form {
                unitsAndRecords
                workout
                media
                iCloud
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
            .accessibilityElement(children: .combine)
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
            // TODO(media): MediaStore has no start/stop hook for a bulk download yet (only `prefetch(sourceIDs:scheme:)`,
            // which needs a catalog-wide id list and a Wi-Fi-only session); for now the choice is only persisted.
            Toggle("Download all videos", isOn: bound.downloadAllVideos)
                .accessibilityLabel("Download all videos")
                .accessibilityIdentifier("settings.downloadAllVideos")
        } header: {
            Text("Media")
        } footer: {
            Text("Downloads over Wi-Fi only.")
        }
    }

    private var iCloud: some View {
        Section {
            // No iCloud entitlement and a local-only container yet, so there is no account status to read.
            LabeledContent("Status", value: "Not set up yet")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("iCloud status")
                .accessibilityValue("Not set up yet")
                .accessibilityIdentifier("settings.iCloudStatus")
        } header: {
            Text("iCloud")
        } footer: {
            Text("Sync turns on once the app is signed.")
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
