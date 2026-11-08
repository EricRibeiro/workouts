import Foundation

public nonisolated enum HeartRateSeries {
    /// Drops the samples from before the workout started (negative offsets, which the matcher allows when the Watch
    /// workout began early), keeping the last of them as a single point at offset 0 so the line still starts at the
    /// right value. Returns the points sorted by offset. Clamping them to 0 instead would stack the warm-up at x=0.
    public static func clippedToStart(_ points: [HeartRatePoint]) -> [HeartRatePoint] {
        let sorted = points.sorted { $0.offset < $1.offset }
        guard let firstOnOrAfter = sorted.firstIndex(where: { $0.offset >= 0 }) else {
            // Every sample is before the start: only the last one carries over.
            return sorted.last.map { [HeartRatePoint(offset: 0, bpm: $0.bpm)] } ?? []
        }
        var result = Array(sorted[firstOnOrAfter...])
        if firstOnOrAfter > 0, result.first?.offset != 0 {
            result.insert(HeartRatePoint(offset: 0, bpm: sorted[firstOnOrAfter - 1].bpm), at: 0)
        }
        return result
    }

    /// The peak to caption a chart drawn from `clipped` (the output of ``clippedToStart(_:)``): the highest plotted sample, so
    /// the caption never exceeds the line. The stored whole-workout max can come from the lead-in the clip dropped; an
    /// empty series falls back to `stored`.
    public static func plottedMaximum(of clipped: [HeartRatePoint], storedMaximum stored: Double?) -> Double? {
        clipped.map(\.bpm).max() ?? stored
    }

    /// The average to caption a chart drawn from `clipped` (the output of ``clippedToStart(_:)``): the time-weighted mean of
    /// the plotted line (trapezoid over consecutive offsets), so Avg covers the same span as ``plottedMaximum(of:storedMaximum:)``.
    /// The stored whole-workout average includes the clipped lead-in; an empty series falls back to `stored`, and a single
    /// point or zero span returns that point's bpm.
    public static func plottedAverage(of clipped: [HeartRatePoint], storedAverage stored: Double?) -> Double? {
        guard let first = clipped.first, let last = clipped.last else { return stored }
        let span = last.offset - first.offset
        guard span > 0 else { return first.bpm }
        let area = zip(clipped, clipped.dropFirst()).reduce(0.0) { sum, pair in
            sum + (pair.0.bpm + pair.1.bpm) / 2 * (pair.1.offset - pair.0.offset)
        }
        return area / span
    }

    /// Reduces `points` to at most `maxPoints` for a small chart.
    ///
    /// Points are sorted by offset and split into `maxPoints` equal-width time buckets. Each non-empty bucket becomes one
    /// point at the bucket's mean offset with the bucket's mean bpm, except the bucket that holds the overall peak, which
    /// emits the peak sample itself, so the chart's highest point always equals the true max bpm.
    /// Input at or under `maxPoints` is returned sorted and unchanged.
    public static func downsample(_ points: [HeartRatePoint], maxPoints: Int) -> [HeartRatePoint] {
        guard maxPoints > 0, !points.isEmpty else { return [] }
        let sorted = points.sorted { $0.offset < $1.offset }
        guard sorted.count > maxPoints, let first = sorted.first, let last = sorted.last else { return sorted }

        let span = last.offset - first.offset
        let peak = sorted.max { $0.bpm < $1.bpm } ?? first
        guard span > 0 else { return [peak] }

        var buckets = Array(repeating: [HeartRatePoint](), count: maxPoints)
        for point in sorted {
            let raw = Int((point.offset - first.offset) / span * Double(maxPoints))
            buckets[min(maxPoints - 1, max(0, raw))].append(point)
        }
        return buckets.compactMap { bucket in
            guard !bucket.isEmpty else { return nil }
            if bucket.contains(peak) { return peak }
            let count = Double(bucket.count)
            return HeartRatePoint(
                offset: bucket.reduce(0) { $0 + $1.offset } / count,
                bpm: bucket.reduce(0) { $0 + $1.bpm } / count
            )
        }
    }
}
