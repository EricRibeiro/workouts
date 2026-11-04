//
//  RestCustomSheet.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// "Custom…" from the rest menu: minutes and seconds wheels (SwiftUI has no countdown `DatePicker`) and a Start item.
/// Start begins the rest, which also records the length in the saved customs (newest first, no defaults, max 6).
struct RestCustomSheet: View {
    @Environment(ActiveWorkoutEngine.self) private var engine: ActiveWorkoutEngine?
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 1
    @State private var seconds = 0

    private var total: Int { minutes * 60 + seconds }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Minutes", selection: $minutes) {
                    ForEach(0...60, id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.wheel)
                .accessibilityLabel("Minutes")
                .accessibilityIdentifier("rest.custom.minutes")
                Picker("Seconds", selection: $seconds) {
                    ForEach(0...59, id: \.self) { Text("\($0) sec").tag($0) }
                }
                .pickerStyle(.wheel)
                .accessibilityLabel("Seconds")
                .accessibilityIdentifier("rest.custom.seconds")
            }
            .padding(.horizontal)
            .navigationTitle("Custom Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("rest.custom.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", systemImage: "checkmark", action: start)
                        .disabled(!RestTimer.durationRange.contains(total))
                        .accessibilityLabel("Start")
                        .accessibilityIdentifier("rest.custom.start")
                }
            }
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("screen.restCustom")
    }

    private func start() {
        // The engine saves a non-default length to the customs list as part of starting.
        try? engine?.startRest(seconds: total)
        dismiss()
    }
}
