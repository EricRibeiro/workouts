//
//  RestTimerPickerSheet.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// "Update Rest Timer…" from a block's header menu (task 3.6): one rest length per exercise, the current one checked.
/// First "Default (m:ss)" (nil: follows the Settings rest), then Off (0: no timer), then the fixed lengths. Choosing a row
/// reports it and closes; Cancel closes without a change. `current` is seconds, 0 for Off, nil for Default.
struct RestTimerPickerSheet: View {
    let current: Int?
    let onSelect: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings: SettingsStore?

    /// Default (nil), Off (0), then the web app's lengths (`workout.md`, "Rest"); a current value outside them (a custom
    /// exercise's own) is kept as a row of its own.
    private var options: [Int?] {
        let fixed = [30, 60, 90, 120, 180, 300]
        let extra = current.map { $0 > 0 && !fixed.contains($0) ? [$0] : [] } ?? []
        return [nil, 0] + (fixed + extra).sorted().map { Optional($0) }
    }

    private var defaultSeconds: Int { settings?.defaultRestSeconds ?? SettingsStore.defaultRestSecondsDefault }

    var body: some View {
        NavigationStack {
            List(options, id: \.self) { seconds in
                Button {
                    onSelect(seconds)
                    dismiss()
                } label: {
                    HStack {
                        Text(title(seconds))
                            .foregroundStyle(.primary)
                        Spacer()
                        if seconds == current {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(.rect)
                }
                .accessibilityAddTraits(seconds == current ? .isSelected : [])
                .accessibilityIdentifier("restTimer.option.\(seconds.map(String.init) ?? "default")")
            }
            .navigationTitle("Rest Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CancelToolbarItem(id: "restTimer.cancel") { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("restTimer.sheet")
    }

    private func title(_ seconds: Int?) -> String {
        guard let seconds else { return "Default (\(clock(defaultSeconds)))" }
        return clock(seconds)
    }

    private func clock(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : ClockFormat.clock(seconds: seconds)
    }
}
