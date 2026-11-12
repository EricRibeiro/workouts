import XCTest

extension XCUIElement {
    /// Waits for the element to stop existing; true once it is gone, false on timeout.
    func waitUntilGone(timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}

extension XCUIElement {
    /// Polls the element's frame every 0.25 s until two consecutive reads are equal (keyboard avoidance and reveal scrolls
    /// have finished moving it) and returns that frame. Fails the test on `timeout` and returns the last read.
    @MainActor @discardableResult
    func waitUntilFrameSettles(
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGRect {
        let deadline = Date().addingTimeInterval(timeout)
        var last = frame
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            let current = frame
            if current == last { return current }
            last = current
        }
        XCTFail("frame still moving after \(timeout)s: \(last)", file: file, line: line)
        return last
    }
}

extension XCUIElement {
    /// Asserts the element is absent now and does not show up within `duration`. For an element that must never appear: call
    /// it after a positive anchor proved the screen settled (a bare `XCTAssertFalse(x.exists)` right after a tap passes
    /// when `x` has merely not appeared yet). A wait on appearance, not a sleep: it fails as soon as the element shows.
    @MainActor
    func assertStaysAbsent(
        for duration: TimeInterval = 1,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(waitForExistence(timeout: duration), message(), file: file, line: line)
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

extension XCUIApplication {
    /// Asserts, without waiting, that a pushed screen's chrome is already on screen: the navigation bar's `title` (when
    /// given) and every button in `buttons` (by identifier). The first frame of a push must already have its bars (DECISIONS
    /// "Pushed-screen chrome"); pair it with `-slowLoads` so the content is still loading when this runs.
    @MainActor
    func assertChromeImmediately(
        title: String? = nil,
        buttons identifiers: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let title {
            XCTAssertTrue(
                // Any element type: a bar with a title menu (the past editor's) exposes its title as a button.
                navigationBars.descendants(matching: .any).matching(
                    NSPredicate(format: "label == %@", title)
                ).firstMatch.exists,
                "no title \(title) in the navigation bar at the push",
                file: file,
                line: line
            )
        }
        for identifier in identifiers {
            XCTAssertTrue(buttons[identifier].exists, "no \(identifier) at the push", file: file, line: line)
        }
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
