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
    /// Starts at half height and only the person's drag changes it. A segment tap does not grow it: a sheet nested in the tab
    /// shell ignores programmatic detent changes on iOS 27.2, so the behaviour would differ by entry point. DEBUG can start it large.
    @State private var detent: PresentationDetent = Self.initialDetent
    /// The size the sheet's content has right now (it changes with the detent and the pose).
    @State private var contentSize: CGSize = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
    /// What the hero leaves free below it so the name and the segmented control stay on screen at the medium detent.
    /// Measured against the content height, which is the sheet's height less its top (grabber) inset, so this is the stack
    /// spacing, the title, the control and a small bottom margin minus that inset. 76 pt keeps closed portrait's 16:9 hero
    /// uncapped (it needs 235 pt of 314). Scales with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var belowHeroReserve: CGFloat = 76

    /// The hero's height limit. Where the 16:9 hero (card inset 16 pt each side) already leaves `belowHeroReserve`, there
    /// is no limit, so closed portrait is untouched. Where it does not, the hero is capped with one more `heroMargin`,
    /// so the control keeps a gap above the sheet's bottom edge and home indicator.
    private var heroMaxHeight: CGFloat {
        let natural = (contentSize.width - 32) * 9 / 16
        let room = contentSize.height - belowHeroReserve
        guard natural > room else { return .infinity }
        return max(room - heroMargin, 72)
    }

    private let heroMargin: CGFloat = 16

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
                .environment(\.exerciseHeroSheetMaxHeight, heroMaxHeight)
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: {
                    contentSize = $0
                }
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
        // Like every other sheet: a centered card on the regular-width Duo, the detents on compact.
        .presentationPlacement(.center)
        // The detail can report a save failure (the pre-load flush): the root's alert sits under this sheet, so host it here.
        .sheetSaveErrorHost()
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
