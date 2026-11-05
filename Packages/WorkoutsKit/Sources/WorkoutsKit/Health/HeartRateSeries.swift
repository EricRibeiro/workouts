import Foundation

public nonisolated enum HeartRateSeries {
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
