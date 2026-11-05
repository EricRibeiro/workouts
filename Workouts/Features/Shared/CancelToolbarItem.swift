import SwiftUI

/// The leading "Cancel" (xmark) item of a sheet or form. Every caller used to repeat the button,
/// its accessibility label and its identifier; only the identifier and the action differ.
/// Screens that attach a confirmation dialog to the button keep their own item.
struct CancelToolbarItem: ToolbarContent {
    let id: String
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", systemImage: "xmark", action: action)
                .accessibilityLabel("Cancel")
                .accessibilityIdentifier(id)
        }
    }
}
