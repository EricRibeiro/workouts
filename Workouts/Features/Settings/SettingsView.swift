//
//  SettingsView.swift
//  Workouts
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {}
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

#Preview {
    SettingsView()
}
