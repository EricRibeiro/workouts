import Testing

@testable import Workouts

@MainActor
struct WorkoutLinkRouterTests {
    @Test func aRequestIsConsumedOnce() {
        let router = WorkoutLinkRouter()
        router.request()
        #expect(router.consume())
        #expect(!router.consume())
    }

    @Test func consumingWithoutARequestIsFalse() {
        #expect(!WorkoutLinkRouter().consume())
    }

    @Test func repeatedRequestsCollapseIntoOne() {
        let router = WorkoutLinkRouter()
        router.request()
        router.request()
        #expect(router.consume())
        #expect(!router.consume())
    }

    @Test func isPendingTracksTheRequest() {
        let router = WorkoutLinkRouter()
        #expect(!router.isPending)
        router.request()
        #expect(router.isPending)
        _ = router.consume()
        #expect(!router.isPending)
    }
}
