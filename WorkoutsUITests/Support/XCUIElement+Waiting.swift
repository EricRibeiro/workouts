import XCTest

extension XCUIElement {
    /// Waits for the element to stop existing; true once it is gone, false on timeout.
    func waitUntilGone(timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}
