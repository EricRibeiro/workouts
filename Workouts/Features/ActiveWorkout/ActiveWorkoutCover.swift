//
//  ActiveWorkoutCover.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// Spike (0.5b) for the active-workout cover: compact shows one placeholder screen, regular shows an
/// `ArrangementView` (primary: Sets, secondary: Exercise + Rest). Replaced by the real screen in 2.10.
struct ActiveWorkoutCover: View {
    let minimise: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            Group {
                if horizontalSizeClass == .regular {
                    ArrangementView {
                        pane("Sets", color: .accentColor)
                    } secondary: {
                        VStack(spacing: 12) {
                            pane("Exercise", color: .green)
                            pane("Rest", color: .orange)
                        }
                    }
                } else {
                    pane("Sets", color: .accentColor)
                }
            }
            .padding()
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Minimise", systemImage: "chevron.down", action: minimise)
                        .accessibilityLabel("Minimise")
                        .accessibilityIdentifier("cover.minimise")
                }
            }
        }
        .accessibilityIdentifier("screen.activeWorkout")
    }

    private func pane(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.title2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.opacity(0.2), in: .rect(cornerRadius: 16))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title) pane")
            .accessibilityIdentifier("cover.pane.\(title.lowercased())")
    }
}

#Preview {
    ActiveWorkoutCover(minimise: {})
}
