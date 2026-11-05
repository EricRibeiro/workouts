//
//  ExerciseInfoSheet.swift
//  Workouts
//

import SwiftUI

/// The exercise whose info sheet is presented.
struct ExerciseInfoItem: Identifiable {
    let exerciseID: UUID
    var id: UUID { exerciseID }
}

/// The exercise detail (About, History, Charts, Records and the media, full width and uncropped) in a sheet with the system
/// Close button.
struct ExerciseInfoSheet: View {
    let exerciseID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseDetailView(exerciseID: exerciseID)
                .environment(\.exerciseHeroCapped, false)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) {
                            dismiss()
                        }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("exerciseInfo.close")
                    }
                }
        }
    }
}

extension View {
    /// Presents the exercise info sheet (medium and large detents) for the bound exercise; setting the binding to nil
    /// dismisses it.
    func exerciseInfoSheet(exerciseID: Binding<UUID?>) -> some View {
        sheet(
            item: Binding(
                get: { exerciseID.wrappedValue.map(ExerciseInfoItem.init(exerciseID:)) },
                set: { exerciseID.wrappedValue = $0?.exerciseID }
            )
        ) { item in
            ExerciseInfoSheet(exerciseID: item.exerciseID)
                .presentationDetents([.medium, .large])
        }
    }
}
