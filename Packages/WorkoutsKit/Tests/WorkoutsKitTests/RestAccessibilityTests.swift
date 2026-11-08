import Foundation
import Testing

@testable import WorkoutsKit

struct RestAccessibilityTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func ringLabelCountsDownThenSaysRestOver() {
        #expect(RestAccessibility.ringLabel(remaining: 297) == "Rest timer, 4:57")
        #expect(RestAccessibility.ringLabel(remaining: 0.4) == "Rest timer, 0:01")
        #expect(RestAccessibility.ringLabel(remaining: 0) == "Rest over")
        #expect(RestAccessibility.ringLabel(remaining: -2) == "Rest over")
    }

    @Test func resumeStateWhileRestRunsAndInGrace() {
        let now = start.addingTimeInterval(600)
        #expect(
            RestAccessibility.resumeState(startedAt: start, endsAt: now.addingTimeInterval(297), now: now)
                == "rest 4:57"
        )
        #expect(RestAccessibility.resumeState(startedAt: start, endsAt: now, now: now) == "rest over")
        #expect(
            RestAccessibility.resumeState(startedAt: start, endsAt: now.addingTimeInterval(-2), now: now) == "rest over"
        )
    }

    @Test func resumeStateWithoutRestIsElapsedTime() {
        func state(_ seconds: TimeInterval) -> String {
            RestAccessibility.resumeState(startedAt: start, endsAt: nil, now: start.addingTimeInterval(seconds))
        }
        #expect(state(5) == "less than a minute elapsed")
        #expect(state(60) == "1 minute elapsed")
        #expect(state(12 * 60 + 34) == "12 minutes elapsed")
        #expect(state(3600) == "1 hour elapsed")
        #expect(state(3600 + 5 * 60) == "1 hour 5 minutes elapsed")
        #expect(state(2 * 3600 + 60) == "2 hours 1 minute elapsed")
        #expect(state(-30) == "less than a minute elapsed")
    }

    @Test func announcementIsRestOver() {
        #expect(RestAccessibility.overAnnouncement == "Rest over")
    }
}
