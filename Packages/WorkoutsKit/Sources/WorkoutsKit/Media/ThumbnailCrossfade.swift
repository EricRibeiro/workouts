import Foundation

/// The list thumbnails' looping start/end cross-fade, as a pure function of the clock so every visible row stays in
/// step and no row owns a timer.
///
/// Ported from the web app's `thumb-crossfade` (`app/ui/src/styles/exercises.css`): `2.4s ease-in-out infinite
/// alternate` on the end frame, with keyframes `0%, 16% { opacity: 0 }` and `84%, 100% { opacity: 1 }`. Each 2.4 s
/// leg therefore holds the start frame for 16 % (0.384 s), eases the end frame in over 68 % (1.632 s, CSS
/// `ease-in-out` = `cubic-bezier(0.42, 0, 0.58, 1)`) and holds it for 16 %; `alternate` plays the next leg in
/// reverse, so a full loop is 4.8 s. The web starts each row's animation when the row mounts; here the phase comes
/// from absolute time, so rows that scroll in later are in step with the rows already on screen.
public nonisolated enum ThumbnailCrossfade {
    /// One leg (start to end, or back), in seconds.
    public static let legDuration: TimeInterval = 2.4
    /// Fraction of a leg held at the start frame, and at the end frame.
    public static let holdFraction = 0.16

    /// The opacity (0...1) of the end frame laid over the start frame at `time` seconds on the shared clock.
    public static func endOpacity(at time: TimeInterval) -> Double {
        guard time.isFinite else { return 0 }
        let loop = legDuration * 2
        var t = time.truncatingRemainder(dividingBy: loop)
        if t < 0 { t += loop }
        // Forward on the first leg, mirrored on the second (`animation-direction: alternate`).
        let leg = t < legDuration ? t / legDuration : 2 - t / legDuration
        if leg <= holdFraction { return 0 }
        if leg >= 1 - holdFraction { return 1 }
        return easeInOut((leg - holdFraction) / (1 - 2 * holdFraction))
    }

    /// CSS `cubic-bezier(0.42, 0, 0.58, 1)`: solve x(s) = `x` by bisection, return y(s).
    static func easeInOut(_ x: Double) -> Double {
        func bezier(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
            let m = 1 - s
            return 3 * m * m * s * p1 + 3 * m * s * s * p2 + s * s * s
        }
        var low = 0.0
        var high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if bezier(mid, 0.42, 0.58) < x { low = mid } else { high = mid }
        }
        return bezier((low + high) / 2, 0, 1)
    }
}
