import SwiftUI
import UIKit

extension View {
    /// While the search field has the keyboard, a tap anywhere on the screen puts the keyboard away, typed text or not.
    /// The tap still reaches what is under it, so a list row opens on that same tap.
    func dismissSearchKeyboardOnTap(_ isFocused: FocusState<Bool>.Binding) -> some View {
        gesture(SearchKeyboardDismissTap(isFocused: isFocused))
    }
}

/// UIKit because a SwiftUI tap gesture on the root swallows list row taps; this recognizer observes the touch and passes it on.
private struct SearchKeyboardDismissTap: UIGestureRecognizerRepresentable {
    let isFocused: FocusState<Bool>.Binding

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        /// A tap on the search field itself (its Clear text button included) keeps the keyboard.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UISearchBar { return false }
                view = current.superview
            }
            return true
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let recognizer = UITapGestureRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        guard recognizer.state == .ended, isFocused.wrappedValue else { return }
        isFocused.wrappedValue = false
    }
}
