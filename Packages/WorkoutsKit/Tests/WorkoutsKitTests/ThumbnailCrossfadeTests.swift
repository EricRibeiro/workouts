import Testing

@testable import WorkoutsKit

struct ThumbnailCrossfadeTests {
    @Test func holdsTheStartFrameAtTheStartOfEachLoop() {
        #expect(ThumbnailCrossfade.endOpacity(at: 0) == 0)
        #expect(ThumbnailCrossfade.endOpacity(at: 0.38) == 0)
        #expect(ThumbnailCrossfade.endOpacity(at: 4.8) == 0)
    }

    @Test func holdsTheEndFrameAtTheEndOfTheFirstLeg() {
        #expect(ThumbnailCrossfade.endOpacity(at: 2.05) == 1)
        #expect(ThumbnailCrossfade.endOpacity(at: 2.4) == 1)
        #expect(ThumbnailCrossfade.endOpacity(at: 2.75) == 1)
    }

    @Test func fadesHalfwayAtTheMidpointOfEachLeg() {
        #expect(abs(ThumbnailCrossfade.endOpacity(at: 1.2) - 0.5) < 0.001)
        #expect(abs(ThumbnailCrossfade.endOpacity(at: 3.6) - 0.5) < 0.001)
    }

    @Test func fadesOutOnTheSecondLegAndRisesMonotonicallyOnTheFirst() {
        var previous = -1.0
        for step in 0...48 {
            let value = ThumbnailCrossfade.endOpacity(at: Double(step) * 0.05)
            #expect(value >= previous)
            previous = value
        }
        #expect(ThumbnailCrossfade.endOpacity(at: 3.0) > ThumbnailCrossfade.endOpacity(at: 4.0))
    }

    @Test func isPeriodicAndSurvivesOddClocks() {
        #expect(
            abs(ThumbnailCrossfade.endOpacity(at: 1.0) - ThumbnailCrossfade.endOpacity(at: 1.0 + 4.8 * 1000)) < 1e-6
        )
        #expect(ThumbnailCrossfade.endOpacity(at: -3.6) >= 0)
        #expect(ThumbnailCrossfade.endOpacity(at: .nan) == 0)
    }

    @Test func easeInOutIsSymmetricAndFlatAtTheEnds() {
        #expect(abs(ThumbnailCrossfade.easeInOut(0.5) - 0.5) < 1e-6)
        #expect(ThumbnailCrossfade.easeInOut(0.1) < 0.1)
        #expect(ThumbnailCrossfade.easeInOut(0.9) > 0.9)
    }
}
