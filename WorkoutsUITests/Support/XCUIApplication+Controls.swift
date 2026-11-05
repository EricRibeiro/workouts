import XCTest

extension XCUIApplication {
    /// A control by identifier, whatever its automation type. Controls that carry a dialog or menu (Finish, the set
    /// keyboard's Done) can be reported as a Button or a PopUpButton depending on the simulator ("Automation type
    /// mismatch"), so `buttons[id]` can miss them.
    func anyControl(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }
}
