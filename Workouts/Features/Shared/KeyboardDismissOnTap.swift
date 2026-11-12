import SwiftUI
import UIKit

extension View {
    /// While the search field has the keyboard, a tap anywhere on the screen puts the keyboard away, typed text or not.
    /// The tap still reaches what is under it, so a list row opens on that same tap.
    func dismissSearchKeyboardOnTap(_ isFocused: FocusState<Bool>.Binding) -> some View {
        dismissKeyboardOnTap { if isFocused.wrappedValue { isFocused.wrappedValue = false } }
    }

    /// A tap anywhere in this view, outside a text field, calls `dismiss`; the tap still reaches what is under it.
    func dismissKeyboardOnTap(_ dismiss: @escaping () -> Void) -> some View {
        gesture(KeyboardDismissTap(dismiss: dismiss))
    }
}

/// UIKit because a SwiftUI tap gesture on the root swallows list row taps; this recognizer observes the touch and passes it on.
private struct KeyboardDismissTap: UIGestureRecognizerRepresentable {
    let dismiss: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        /// A tap on a text field keeps the keyboard: on the field itself (the search field's Clear button included) or
        /// within the minimum touch target around it, which a cell may focus the field from.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UISearchBar { return false }
                view = current.superview
            }
            guard let root = gestureRecognizer.view else { return true }
            let point = touch.location(in: root)
            let target = UIFontMetrics.default.scaledValue(for: 44)
            return !Self.textFields(in: root).contains { field in
                let frame = field.convert(field.bounds, to: root)
                let pad = max(0, (target - frame.height) / 2)
                return frame.insetBy(dx: 0, dy: -pad).contains(point)
            }
        }

        private static func textFields(in view: UIView) -> [UITextField] {
            if let field = view as? UITextField { return [field] }
            return view.subviews.flatMap(textFields(in:))
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
        if recognizer.state == .ended { dismiss() }
    }
}
