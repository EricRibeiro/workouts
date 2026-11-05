import Foundation

/// A small deterministic generator (StarRandom): the same seed always yields the same sequence, on every platform.
public nonisolated struct StarRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Which colour a celebration star takes; the view maps each role to a theme colour.
public nonisolated enum StarTone: Sendable, Equatable, CaseIterable {
    case accent
    case grey
    case gold
}

/// One falling star's fixed parameters. Lengths are points; angles are degrees; times are seconds.
public nonisolated struct StarParticle: Sendable, Equatable {
    /// Horizontal start as a fraction of the width (`0...1`).
    public let startX: Double
    /// Edge length of the star's square frame.
    public let size: Double
    public let tone: StarTone
    /// Seconds after the start before this star enters.
    public let delay: TimeInterval
    /// Seconds to fall from above the top edge to below the bottom edge.
    public let duration: TimeInterval
    /// Total horizontal travel over the fall (signed).
    public let drift: Double
    /// Rotation speed in degrees per second (signed).
    public let spin: Double
    /// Rotation at the start, in degrees.
    public let phase: Double
    /// Where this star rests in the Reduce Motion scatter, as a fraction of the scatter area's height (`0...1`).
    public let restY: Double
}

/// A star's placement at one instant.
public nonisolated struct StarState: Sendable, Equatable {
    /// Centre of the star, in the field's coordinate space.
    public let x: Double
    public let y: Double
    public let rotation: Double
    public let opacity: Double
}

/// A seeded, deterministic set of falling stars for the finish summary's celebration: no SwiftUI, no randomness at
/// draw time, so the same `(count, seed)` always plays the same animation and the maths is testable on macOS.
public nonisolated struct StarField: Sendable, Equatable {
    /// The last moment anything is visible; at or after this every star has opacity 0.
    public static let totalDuration: TimeInterval = 4.5
    /// Seconds over which the whole field fades out, ending at `totalDuration`.
    public static let fadeDuration: TimeInterval = 0.5
    /// Star counts used by the finish summary.
    public static let plainCount = 140
    public static let recordCount = 200

    public let particles: [StarParticle]

    /// - Parameter goldShare: fraction of stars that are gold (the rest split 2:1 between accent and grey).
    public init(count: Int, seed: UInt64, goldShare: Double = 0) {
        var rng = StarRandom(seed: seed)
        particles = (0..<max(0, count)).map { _ in
            let roll = Double.random(in: 0..<1, using: &rng)
            let tone: StarTone
            if roll < goldShare {
                tone = .gold
            } else {
                tone = Double.random(in: 0..<1, using: &rng) < 2.0 / 3.0 ? .accent : .grey
            }
            let delay = Double.random(in: 0...1.6, using: &rng)
            // delay + duration stays inside the window where the field has not yet fully faded.
            let duration = Double.random(in: 2.0...(Self.totalDuration - delay - 0.4), using: &rng)
            let spin = Double.random(in: 60...220, using: &rng)
            return StarParticle(
                startX: Double.random(in: 0...1, using: &rng),
                size: Double.random(in: 8...22, using: &rng),
                tone: tone,
                delay: delay,
                duration: duration,
                drift: Double.random(in: -40...40, using: &rng),
                spin: Bool.random(using: &rng) ? spin : -spin,
                phase: Double.random(in: 0..<360, using: &rng),
                restY: Double.random(in: 0...1, using: &rng)
            )
        }
    }

    /// A field sized for a finish: more stars, a share of them gold, when the workout set a record.
    public init(hasRecord: Bool, seed: UInt64) {
        self.init(
            count: hasRecord ? Self.recordCount : Self.plainCount,
            seed: seed,
            goldShare: hasRecord ? 0.3 : 0
        )
    }

    /// Where `particle` is `elapsed` seconds after the start, in a field `width` x `height` points. Stars begin one
    /// star-height above the top edge, fall linearly past the bottom edge, and the whole field fades over the last
    /// `fadeDuration`. Opacity is 0 before the star enters, once it has left, and from `totalDuration` on.
    public func state(of particle: StarParticle, at elapsed: TimeInterval, width: Double, height: Double) -> StarState {
        let local = elapsed - particle.delay
        let progress = min(max(local / particle.duration, 0), 1)
        let fade = min(max((Self.totalDuration - elapsed) / Self.fadeDuration, 0), 1)
        let entered = local >= 0 && local <= particle.duration
        let startY = -particle.size
        let endY = height + particle.size
        return StarState(
            x: particle.startX * width + particle.drift * progress,
            y: startY + (endY - startY) * progress,
            rotation: particle.phase + particle.spin * max(local, 0),
            opacity: entered ? fade : 0
        )
    }

    /// The Reduce Motion layout: stars at rest inside a `width` x `height` area, sparse (every third star, at most
    /// `maxCount`) and dimmed so they read as decoration. No time dependence.
    public func scatter(width: Double, height: Double, maxCount: Int = 12) -> [(
        particle: StarParticle, state: StarState
    )] {
        let sparse = particles.enumerated().filter { $0.offset % 3 == 0 }.map(\.element)
        return sparse.prefix(max(0, maxCount)).map { particle in
            (
                particle,
                StarState(
                    x: particle.startX * width,
                    y: particle.restY * height,
                    rotation: particle.phase,
                    opacity: 0.6
                )
            )
        }
    }
}
