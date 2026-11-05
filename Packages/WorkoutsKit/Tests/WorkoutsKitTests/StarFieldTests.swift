import Testing

@testable import WorkoutsKit

@Suite struct StarFieldTests {
    @Test func sameSeedSameParticles() {
        #expect(StarField(count: 40, seed: 7, goldShare: 0.3) == StarField(count: 40, seed: 7, goldShare: 0.3))
        #expect(StarField(count: 40, seed: 7) != StarField(count: 40, seed: 8))
    }

    @Test func finishCountsDependOnRecord() {
        #expect(StarField(hasRecord: false, seed: 1).particles.count == StarField.plainCount)
        #expect(StarField(hasRecord: true, seed: 1).particles.count == StarField.recordCount)
        #expect(StarField(count: -3, seed: 1).particles.isEmpty)
    }

    @Test func goldOnlyWhenAsked() {
        let plain = StarField(hasRecord: false, seed: 3).particles
        #expect(!plain.contains { $0.tone == .gold })
        let record = StarField(hasRecord: true, seed: 3).particles
        #expect(record.contains { $0.tone == .gold })
        #expect(record.contains { $0.tone == .accent })
        #expect(record.contains { $0.tone == .grey })
    }

    @Test func parametersStayInRange() {
        for particle in StarField(count: 200, seed: 11).particles {
            #expect((8...22).contains(particle.size))
            #expect((0...1).contains(particle.startX))
            #expect((0...1).contains(particle.restY))
            #expect(abs(particle.drift) <= 40)
            #expect(particle.delay + particle.duration <= StarField.totalDuration - 0.4 + 1e-9)
        }
    }

    @Test func startsAboveTopEdge() {
        let field = StarField(count: 50, seed: 5)
        for particle in field.particles {
            let state = field.state(of: particle, at: particle.delay, width: 400, height: 800)
            #expect(state.y <= -particle.size + 1e-9)
        }
    }

    @Test func fallsPastBottomAndMovesDown() {
        let field = StarField(count: 20, seed: 9)
        for particle in field.particles {
            let early = field.state(of: particle, at: particle.delay + 0.1, width: 400, height: 800)
            let later = field.state(of: particle, at: particle.delay + particle.duration * 0.5, width: 400, height: 800)
            let last = field.state(of: particle, at: particle.delay + particle.duration, width: 400, height: 800)
            #expect(later.y > early.y)
            #expect(last.y >= 800 + particle.size - 1e-9)
        }
    }

    @Test func invisibleBeforeEntering() {
        let field = StarField(count: 20, seed: 2)
        for particle in field.particles where particle.delay > 0.01 {
            #expect(field.state(of: particle, at: 0, width: 400, height: 800).opacity == 0)
        }
    }

    @Test func fadesToNothingAtTheEnd() {
        let field = StarField(hasRecord: true, seed: 4)
        for particle in field.particles {
            for time in [StarField.totalDuration, StarField.totalDuration + 0.1, 10] {
                #expect(field.state(of: particle, at: time, width: 400, height: 800).opacity == 0)
            }
        }
        #expect(field.particles.allSatisfy { $0.delay + $0.duration < StarField.totalDuration })
    }

    @Test func starsAreFullyOpaqueBeforeTheFadeStarts() {
        let field = StarField(count: 60, seed: 6)
        let time = StarField.totalDuration - StarField.fadeDuration
        for particle in field.particles {
            let opacity = field.state(of: particle, at: time, width: 400, height: 800).opacity
            #expect(opacity == 0 || opacity == 1)
        }
        let mid = StarField.totalDuration - StarField.fadeDuration / 2
        for particle in field.particles {
            let opacity = field.state(of: particle, at: mid, width: 400, height: 800).opacity
            #expect(opacity == 0 || abs(opacity - 0.5) < 1e-9)
        }
    }

    @Test func scatterIsStaticSparseAndInsideTheArea() {
        let field = StarField(hasRecord: true, seed: 8)
        let scatter = field.scatter(width: 300, height: 120)
        #expect(!scatter.isEmpty)
        #expect(scatter.count <= 12)
        for item in scatter {
            #expect((0...300).contains(item.state.x))
            #expect((0...120).contains(item.state.y))
            #expect(item.state.opacity > 0 && item.state.opacity < 1)
        }
        #expect(field.scatter(width: 300, height: 120, maxCount: 0).isEmpty)
        #expect(field.scatter(width: 300, height: 120).map(\.state) == scatter.map(\.state))
    }

    @Test func randomIsDeterministic() {
        var first = StarRandom(seed: 42)
        var second = StarRandom(seed: 42)
        #expect((0..<5).map { _ in first.next() } == (0..<5).map { _ in second.next() })
    }
}
