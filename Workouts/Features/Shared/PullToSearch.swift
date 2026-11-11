import SwiftUI
import WorkoutsKit

extension View {
    /// Sets `isPresented` when the user drags the scroll view down past the threshold at its top and releases, once the
    /// list has come back to rest, like the App Library.
    func pullToSearch(isPresented: Binding<Bool>) -> some View {
        modifier(PullToSearchModifier(isPresented: isPresented))
    }
}

private struct PullToSearchModifier: ViewModifier {
    @Binding var isPresented: Bool
    @State private var trigger = PullToSearchTrigger()

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, newPhase in
                let phase: PullToSearchTrigger.Phase =
                    switch newPhase {
                    case .interacting, .tracking: .interacting
                    case .decelerating, .animating: .settling
                    case .idle: .idle
                    @unknown default: .settling
                    }
                // Waits for rest: presenting search while the list is overscrolled makes the content jump.
                if trigger.phaseChanged(to: phase) && !isPresented { isPresented = true }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                PullToSearch.isPulledPast(
                    contentOffsetY: geometry.contentOffset.y,
                    topInset: geometry.contentInsets.top
                )
            } action: { _, isPulled in
                trigger.pulledPast(isPulled)
            }
    }
}
