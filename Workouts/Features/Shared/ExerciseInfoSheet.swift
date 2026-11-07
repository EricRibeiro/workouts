//
//  ExerciseInfoSheet.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The exercise whose info sheet is presented.
struct ExerciseInfoItem: Identifiable {
    let exerciseID: UUID
    var id: UUID { exerciseID }
}

/// The exercise detail (About, History, Charts, Records and the media, full width and uncropped) in a sheet. There is no
/// Close button: the sheet dismisses by swiping down (and VoiceOver's escape gesture), and its grabber stays visible.
struct ExerciseInfoSheet: View {
    let exerciseID: UUID
    /// Starts at half height; only the user drags it taller (a segment tap does not grow it). DEBUG can start it large.
    @State private var detent: PresentationDetent = Self.initialDetent

    private static var initialDetent: PresentationDetent {
        #if DEBUG
            // `-infoSheetDetent large` presents the gallery's sheet at full height (screenshots).
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-infoSheetDetent"), arguments.indices.contains(index + 1),
                arguments[index + 1] == "large"
            {
                return .large
            }
        #endif
        return .medium
    }

    var body: some View {
        NavigationStack {
            ExerciseDetailView(exerciseID: exerciseID)
                .environment(\.exerciseHeroCapped, false)
                .environment(\.exerciseInfoSheetContent, true)
                // A sheet over the tab shell cannot navigate it: opening a workout would switch tabs behind the sheet.
                // Without `AppNavigation` the history sessions and records render as plain rows (as in the cover).
                .environment(AppNavigation?.none)
                // The closed Duo gives a sheet a vertical bar strip by default, which reserves the trailing column
                // for one Close button. This sheet is better with the full width, so its bar stays horizontal
                // (docs: `toolbarVerticalBehavior(_:)`, "opt out of the vertical bar"). A fixed choice, never toggled.
                .toolbarVerticalBehavior(.disabled)
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
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
        }
    }
}
