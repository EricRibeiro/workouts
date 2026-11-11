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

@Suite struct PullToSearchTriggerTests {
    @Test func releasedWhilePulledOpensOnceAtRest() {
        var trigger = PullToSearchTrigger()
        let fired1 = trigger.phaseChanged(to: .interacting)
        #expect(!fired1)
        trigger.pulledPast(true)
        let fired2 = trigger.phaseChanged(to: .settling)
        #expect(!fired2)
        let fired3 = trigger.phaseChanged(to: .idle)
        #expect(fired3)
    }

    @Test func nothingOpensWhileDraggedPast() {
        var trigger = PullToSearchTrigger()
        _ = trigger.phaseChanged(to: .interacting)
        trigger.pulledPast(true)
        let fired4 = trigger.phaseChanged(to: .interacting)
        #expect(!fired4)
    }

    @Test func interactingStraightToIdleWhilePulledFiresInOneCall() {
        var trigger = PullToSearchTrigger()
        _ = trigger.phaseChanged(to: .interacting)
        trigger.pulledPast(true)
        let fired5 = trigger.phaseChanged(to: .idle)
        #expect(fired5)
    }

    @Test func draggedBackAboveThresholdBeforeLiftingDoesNotArm() {
        var trigger = PullToSearchTrigger()
        _ = trigger.phaseChanged(to: .interacting)
        trigger.pulledPast(true)
        trigger.pulledPast(false)
        let fired6 = trigger.phaseChanged(to: .settling)
        #expect(!fired6)
        let fired7 = trigger.phaseChanged(to: .idle)
        #expect(!fired7)
    }

    @Test func newTouchCancelsPendingOpen() {
        var trigger = PullToSearchTrigger()
        _ = trigger.phaseChanged(to: .interacting)
        trigger.pulledPast(true)
        _ = trigger.phaseChanged(to: .settling)
        let fired8 = trigger.phaseChanged(to: .interacting)
        #expect(!fired8)
        trigger.pulledPast(false)
        let fired9 = trigger.phaseChanged(to: .settling)
        #expect(!fired9)
        let fired10 = trigger.phaseChanged(to: .idle)
        #expect(!fired10)
    }

    @Test func flingThatOverscrollsOnlyWhileSettlingNeverFires() {
        var trigger = PullToSearchTrigger()
        _ = trigger.phaseChanged(to: .interacting)
        _ = trigger.phaseChanged(to: .settling)
        trigger.pulledPast(true)
        trigger.pulledPast(false)
        let fired11 = trigger.phaseChanged(to: .idle)
        #expect(!fired11)
        trigger.pulledPast(true)
        let fired12 = trigger.phaseChanged(to: .idle)
        #expect(!fired12)
    }

    @Test func firesOnlyOnce() {
        var trigger = PullToSearchTrigger()
        _ = trigger.phaseChanged(to: .interacting)
        trigger.pulledPast(true)
        _ = trigger.phaseChanged(to: .settling)
        let fired13 = trigger.phaseChanged(to: .idle)
        #expect(fired13)
        let fired14 = trigger.phaseChanged(to: .idle)
        #expect(!fired14)
    }
}
