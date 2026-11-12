import SwiftUI

extension View {
    /// While the search field has the keyboard and nothing is typed, a tap anywhere on the screen puts the keyboard away.
    /// Off once there is a query: a tap gesture up here wins over a list row's selection, and a result must open on the
    /// first tap.
    func dismissSearchKeyboardOnTap(_ isFocused: FocusState<Bool>.Binding, whileEmpty query: String) -> some View {
        simultaneousGesture(
            TapGesture().onEnded { isFocused.wrappedValue = false },
            isEnabled: isFocused.wrappedValue && query.isEmpty
        )
    }
}
