//
//  RestTimerPickerSheet.swift
//  Workouts
//

import SwiftUI

/// "Update Rest Timer…" from a block's header menu (task 3.6): one rest length per exercise, from Off to 5:00, the current one
/// checked. Choosing a row reports it and closes; Cancel closes without a change. `current` is seconds, nil or 0 for Off.
struct RestTimerPickerSheet: View {
    let current: Int?
    let onSelect: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Off (nil) then the web app's lengths (`workout.md`, "Rest").
    private static let options: [Int?] = [nil, 30, 60, 90, 120, 180, 300]

    var body: some View {
        NavigationStack {
            List(Self.options, id: \.self) { seconds in
                Button {
                    onSelect(seconds)
                    dismiss()
                } label: {
                    HStack {
                        Text(Self.title(seconds))
                            .foregroundStyle(.primary)
                        Spacer()
                        if Self.isSelected(seconds, current: current) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(.rect)
                }
                .accessibilityAddTraits(Self.isSelected(seconds, current: current) ? .isSelected : [])
                .accessibilityIdentifier("restTimer.option.\(seconds ?? 0)")
            }
            .navigationTitle("Rest Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("restTimer.cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("restTimer.sheet")
    }

    private static func title(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "Off" }
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    private static func isSelected(_ seconds: Int?, current: Int?) -> Bool {
        (seconds ?? 0) == (current ?? 0)
    }
}
