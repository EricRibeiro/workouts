import XCTest

extension XCUIElement {
    /// Waits for the element to stop existing; true once it is gone, false on timeout.
    func waitUntilGone(timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}

extension XCUIApplication {
    /// Dismisses the sheet whose content starts at `top` (any element near the sheet's top, such as its detail's name) by
    /// dragging down from just above that element to the bottom of the window: the grabber's area, which dismisses at
    /// every detent without scrolling the content. The exercise info sheet has no Close button.
    func dismissSheetBySwiping(top: XCUIElement) {
        let window = windows.firstMatch
        let height = window.frame.height
        let start = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.frame.width / 2, dy: max(top.frame.minY - 12, 1)))
        let end = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.frame.width / 2, dy: height - 2))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }
}

extension XCTestCase {
    /// Waits until `condition` holds (evaluated on the main actor, so it may read elements); true once it does, false on timeout.
    @MainActor @discardableResult
    func waitUntil(timeout: TimeInterval = 5, _ condition: @escaping @MainActor () -> Bool) -> Bool {
        let holds = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in MainActor.assumeIsolated { condition() } },
            object: nil
        )
        return XCTWaiter().wait(for: [holds], timeout: timeout) == .completed
    }
}
