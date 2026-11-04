//
//  SetKeyboardToolbar.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The keyboard accessory group of the set table (task 2.2b, `DECISIONS.md` "Keyboard"): −step, +step, Previous, Next and
/// Done, installed as a `.keyboard` `ToolbarItemGroup`. It never touches the engine; the table supplies closures that act on
/// whichever field has focus, and `SetKeyboard` (kit) decides step sizes and the Next order.
///
/// `step` is a −1 / +1 step press. `previous` copies the previous set into the focused row. `next` moves focus
/// (weight → reps → next row's weight) and dismisses after the last field. `done` only closes the keyboard; it never checks.
/// While a rest runs (`rest` non-nil) the group starts with its countdown, Skip and +30 s.
struct SetKeyboardToolbar: ViewModifier {
    let step: (SetKeyboard.Direction) -> Void
    let previous: () -> Void
    let next: () -> Void
    let done: () -> Void
    var rest: SetTableRest?

    func body(content: Content) -> some View {
        content
            .toolbar {
                // Three groups so the overflow order is ours: the rest trio folds first (the toolbar strip already has the
                // countdown, Skip and +30), Next and Done never fold.
                ToolbarItemGroup(placement: .keyboard) {
                    if let rest {
                        Text(timerInterval: min(.now, rest.endsAt)...rest.endsAt, countsDown: true)
                            .font(.body.monospacedDigit())
                            .accessibilityLabel("Rest remaining")
                            .accessibilityIdentifier("rest.keyboard.countdown")

                        Button(action: rest.skip) {
                            Label("Skip", systemImage: "forward.end")
                        }
                        .accessibilityLabel("Skip rest")
                        .accessibilityIdentifier("rest.keyboard.skip")

                        Button(action: rest.add30) {
                            Label("Add 30 seconds", systemImage: "goforward.30")
                        }
                        .accessibilityLabel("Add 30 seconds")
                        .accessibilityIdentifier("rest.keyboard.plus30")
                    }
                }
                .visibilityPriority(.low)

                ToolbarItemGroup(placement: .keyboard) {
                    Button {
                        step(.decrement)
                    } label: {
                        Label("Decrease", systemImage: "minus")
                    }
                    .accessibilityLabel("Decrease by one step")
                    .accessibilityIdentifier("setkeyboard.minus")

                    Button {
                        step(.increment)
                    } label: {
                        Label("Increase", systemImage: "plus")
                    }
                    .accessibilityLabel("Increase by one step")
                    .accessibilityIdentifier("setkeyboard.plus")

                    Button(action: previous) {
                        Label("Previous", systemImage: "arrow.uturn.backward")
                    }
                    .accessibilityLabel("Copy previous set")
                    .accessibilityIdentifier("setkeyboard.previous")
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Button(action: next) {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .accessibilityLabel("Next field")
                    .accessibilityIdentifier("setkeyboard.next")

                    Button(action: done) {
                        Label("Done", systemImage: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Done")
                    .accessibilityHint("Closes the keyboard")
                    .accessibilityIdentifier("setkeyboard.done")
                }
                .visibilityPriority(.high)
            }
    }
}

extension View {
    /// Installs the set keyboard's accessory group; see `SetKeyboardToolbar`.
    func setKeyboardToolbar(
        step: @escaping (SetKeyboard.Direction) -> Void,
        previous: @escaping () -> Void,
        next: @escaping () -> Void,
        done: @escaping () -> Void,
        rest: SetTableRest? = nil
    ) -> some View {
        modifier(SetKeyboardToolbar(step: step, previous: previous, next: next, done: done, rest: rest))
    }
}
