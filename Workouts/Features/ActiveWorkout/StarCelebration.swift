//
//  StarCelebration.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// A short fall of stars behind the finish summary. The motion comes from `StarField` (WorkoutsKit); this view only
/// draws it. It plays once for `StarField.totalDuration`, then removes its timeline so nothing keeps running.
/// With Reduce Motion on, it draws a sparse static scatter across the top of its area instead.
struct StarCelebration: View {
    let field: StarField

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = StartClock()
    @State private var finished = false

    init(hasRecord: Bool, seed: UInt64) {
        field = StarField(hasRecord: hasRecord, seed: seed)
    }

    var body: some View {
        Group {
            if reduceMotion {
                canvas(elapsed: nil)
            } else if !finished {
                TimelineView(.animation) { timeline in
                    canvas(elapsed: timeline.date.timeIntervalSince(clock.start(at: timeline.date)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(StarField.totalDuration + 0.1))
            finished = true
        }
    }

    /// `elapsed == nil` draws the Reduce Motion scatter (top ~30% of the area, where the header sits); the animated
    /// path always passes an elapsed time, so it never draws the scatter.
    private func canvas(elapsed: TimeInterval?) -> some View {
        Canvas { context, size in
            // One resolved image per tone per frame: recolouring a resolved image per star re-renders it every draw.
            let images = Dictionary(
                uniqueKeysWithValues: StarTone.allCases.map { tone in
                    var image = context.resolve(Image(systemName: "star.fill"))
                    image.shading = shading(for: tone)
                    return (tone, image)
                }
            )
            let placements: [(StarParticle, StarState)]
            if let elapsed {
                placements = field.particles.map {
                    ($0, field.state(of: $0, at: elapsed, width: size.width, height: size.height))
                }
            } else {
                placements = field.scatter(width: size.width, height: size.height * 0.3).map { ($0.particle, $0.state) }
            }
            for (particle, state) in placements where state.opacity > 0 {
                var star = context
                star.opacity = state.opacity
                star.translateBy(x: state.x, y: state.y)
                star.rotate(by: .degrees(state.rotation))
                guard let image = images[particle.tone] else { continue }
                let side = particle.size
                star.draw(image, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
            }
        }
    }

    /// The animation's start, taken from the first timeline date. A reference type on purpose: `TimelineView` keeps the
    /// content closure from the first body pass, and a `@State` value read through that stale copy stays at its
    /// initial value (nil), which is how the scatter used to be drawn forever. A shared object sees every write.
    private final class StartClock {
        private var date: Date?

        func start(at now: Date) -> Date {
            if let date { return date }
            date = now
            return now
        }
    }

    private func shading(for tone: StarTone) -> GraphicsContext.Shading {
        switch tone {
        case .accent: .color(.accentColor)
        case .grey: .style(.secondary)
        case .gold: .color(.yellow)
        }
    }
}

#Preview("Stars") {
    StarCelebration(hasRecord: true, seed: 615)
}
