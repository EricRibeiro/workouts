import Testing

@testable import WorkoutsKit

@Suite struct PullToSearchTests {
    @Test func atRestIsNotPulled() {
        #expect(!PullToSearch.isPulledPast(contentOffsetY: 0, topInset: 0))
        #expect(!PullToSearch.isPulledPast(contentOffsetY: -100, topInset: 100))
    }

    @Test func scrolledIntoContentIsNotPulled() {
        #expect(!PullToSearch.isPulledPast(contentOffsetY: 300, topInset: 0))
        #expect(!PullToSearch.isPulledPast(contentOffsetY: 200, topInset: 100))
    }

    @Test func justUnderThresholdIsNotPulled() {
        #expect(!PullToSearch.isPulledPast(contentOffsetY: -49.9, topInset: 0))
        #expect(!PullToSearch.isPulledPast(contentOffsetY: -149.9, topInset: 100))
    }

    @Test func exactlyAtThresholdIsPulled() {
        #expect(PullToSearch.isPulledPast(contentOffsetY: -50, topInset: 0))
        #expect(PullToSearch.isPulledPast(contentOffsetY: -150, topInset: 100))
    }

    @Test func pastThresholdIsPulled() {
        #expect(PullToSearch.isPulledPast(contentOffsetY: -120, topInset: 0))
        #expect(PullToSearch.isPulledPast(contentOffsetY: -220, topInset: 100))
    }

    @Test func customThreshold() {
        #expect(PullToSearch.isPulledPast(contentOffsetY: -20, topInset: 0, threshold: 20))
        #expect(!PullToSearch.isPulledPast(contentOffsetY: -19, topInset: 0, threshold: 20))
    }
}
