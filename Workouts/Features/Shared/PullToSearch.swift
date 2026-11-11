import SwiftUI
import WorkoutsKit

extension View {
    /// Sets `isPresented` when the user drags the scroll view down past the threshold at its top, like the App Library.
    func pullToSearch(isPresented: Binding<Bool>) -> some View {
        modifier(PullToSearchModifier(isPresented: isPresented))
    }
}

private struct PullToSearchModifier: ViewModifier {
    @Binding var isPresented: Bool
    @State private var isInteracting = false

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, newPhase in
                isInteracting = newPhase == .interacting
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                PullToSearch.isPulledPast(
                    contentOffsetY: geometry.contentOffset.y,
                    topInset: geometry.contentInsets.top
                )
            } action: { _, isPulled in
                // Finger down only: a fling that bounces at the top after the finger lifted must not open search.
                if isPulled && isInteracting && !isPresented { isPresented = true }
            }
    }
}
