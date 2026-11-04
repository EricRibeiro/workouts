//
//  SettingsView.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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

#Preview {
    if let container = try? ModelContainer.preview(catalog: LibraryCatalog.bundled(in: .main)) {
        SettingsView().modelContainer(container)
    } else {
        SettingsView()
    }
}
