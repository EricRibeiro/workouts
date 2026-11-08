import Foundation

/// What a progress chart plots for one exercise.
public nonisolated enum ChartMetric: String, Codable, CaseIterable, Sendable {
    case e1rm
    case maxWeight
    case volume
    case totalReps
    case bestReps
}

/// One session on a chart.
public nonisolated struct ChartPoint: Hashable, Sendable {
    public var workoutID: UUID
    public var time: Date
    /// In the display unit (weights, volume, e1RM) or a plain count (reps).
    public var value: Double
    /// True when an e1RM point came from more than 12 reps.
    public var lowConfidence: Bool

    public init(workoutID: UUID, time: Date, value: Double, lowConfidence: Bool = false) {
        self.workoutID = workoutID
        self.time = time
        self.value = value
        self.lowConfidence = lowConfidence
    }
}

/// Stable sort by time: sessions with equal times keep their input order.
nonisolated func sortedByTime(_ sessions: [Session]) -> [Session] {
    sessions.enumerated()
        .sorted { a, b in a.element.time != b.element.time ? a.element.time < b.element.time : a.offset < b.offset }
        .map(\.element)
}

/// Whether e1RM `value`/`low` strictly beats the current one (confident always beats low-confidence; otherwise the
/// larger wins, with the 1e-6 tolerance so a tie never replaces the earlier holder).
nonisolated func e1rmBeats(_ value: Double, low: Bool, _ current: Double, currentLow: Bool) -> Bool {
    if low != currentLow { return !low }
    return compareKg(value, current) > 0
}

/// Rows sharing a workout and exercise merged into one session each, in first-seen order.
nonisolated func mergedByWorkout(_ sessions: [Session]) -> [Session] {
    var groups: [[Session]] = []
    var groupOf: [WorkoutExerciseKey: Int] = [:]
    for session in sessions {
        let key = WorkoutExerciseKey(workoutID: session.workoutID, exerciseID: session.exerciseID)
        if let group = groupOf[key] {
            groups[group].append(session)
        } else {
            groupOf[key] = groups.count
            groups.append([session])
        }
    }
    return groups.map { $0.count == 1 ? $0[0] : mergedSession($0) }
}

/// One point per session, stable-sorted by time. Rows of one exercise in one workout are one session (merged with
/// ``mergedSession(_:)``, as PRs and the Finish screen judge them), so a repeated exercise never plots two points.
///
/// A session with no counted set that has reps has no point for any metric. A metric that does not apply to the
/// session's weight type (e1RM for rep types and assisted, volume for assisted) yields no point for that session, so
/// the series is `[]` when it applies to none of them. Per metric:
/// - `e1rm`: best e1RM of the session (confident beats low-confidence); strength types only; sets without weight give
///   no point.
/// - `maxWeight`: heaviest counted set with reps; assisted: the lowest assistance. Unloaded sessions of non-assisted
///   types have no point.
/// - `volume`: the session volume (0 for unloaded rep types; not for assisted).
/// - `totalReps`: reps over counted sets. `bestReps`: most reps in one counted set.
public nonisolated func chartSeries(_ sessions: [Session], metric: ChartMetric, options: RecordsOptions)
    -> [ChartPoint]
{
    var points: [ChartPoint] = []
    for session in sortedByTime(mergedByWorkout(sessions)) {
        let category = session.weightType.category
        let withReps = countedSets(session.sets).filter { $0.reps > 0 }
        guard !withReps.isEmpty else { continue }
        var point = ChartPoint(workoutID: session.workoutID, time: session.time, value: 0)

        switch metric {
        case .e1rm:
            guard category == .strength else { continue }
            var best = 0.0
            var bestLow = false
            for set in withReps where set.weightKg > 0 {
                let estimate = e1rm(weight: set.weightKg, reps: set.reps, formula: options.formula)
                if best <= 0 || e1rmBeats(estimate.value, low: estimate.lowConfidence, best, currentLow: bestLow) {
                    best = estimate.value
                    bestLow = estimate.lowConfidence
                }
            }
            guard best > 0 else { continue }
            point.value = displayedAggregate(kg: best, unit: options.displayUnit)
            point.lowConfidence = bestLow
        case .maxWeight:
            var pick = withReps[0]
            for set in withReps.dropFirst() {
                let order = compareKg(set.weightKg, pick.weightKg)
                if category == .assisted ? order < 0 : order > 0 { pick = set }
            }
            if category != .assisted && pick.weightKg <= 0 { continue }
            point.value = displayedWeight(pick, unit: options.displayUnit)
        case .volume:
            guard category != .assisted else { continue }
            point.value = volume(of: session.sets, weightType: session.weightType, displayUnit: options.displayUnit)
        case .totalReps:
            point.value = Double(withReps.reduce(0) { $0 + $1.reps })
        case .bestReps:
            point.value = Double(withReps.map(\.reps).max() ?? 0)
        }
        points.append(point)
    }
    return points
}

extension ChartMetric {
    /// The metric chips of an exercise's chart, default first (`docs/port/screens/exercises.md` section 2, "Charts
    /// tab"): strength `e1rm`, `maxWeight`, `volume`, `totalReps`, `bestReps`; rep types `bestReps`, `totalReps`,
    /// `maxWeight`, `volume`; assisted `maxWeight` (least assistance), `bestReps`, `totalReps`.
    public static func available(for category: WeightCategory) -> [ChartMetric] {
        switch category {
        case .strength: [.e1rm, .maxWeight, .volume, .totalReps, .bestReps]
        case .repBased: [.bestReps, .totalReps, .maxWeight, .volume]
        case .assisted: [.maxWeight, .bestReps, .totalReps]
        }
    }

    public static func defaultMetric(for category: WeightCategory) -> ChartMetric {
        available(for: category)[0]
    }

    /// The chip title.
    public func title(for category: WeightCategory) -> String {
        switch self {
        case .e1rm: "Est. 1RM"
        case .maxWeight: category == .assisted ? "Least assistance" : "Max weight"
        case .volume: "Volume"
        case .totalReps: "Total reps"
        case .bestReps: "Best reps"
        }
    }

    /// Whether values are weights in the display unit (so the axis and readout carry the unit suffix).
    public var isWeightValued: Bool {
        switch self {
        case .e1rm, .maxWeight, .volume: true
        case .totalReps, .bestReps: false
        }
    }
}

/// How far back a chart reaches.
public nonisolated enum ChartRange: String, CaseIterable, Sendable, Identifiable {
    case month = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "1Y"
    case all = "All"

    public var id: String { rawValue }

    /// The default range.
    public static let standard = ChartRange.threeMonths

    /// The earliest included instant for `now`; nil for `all`.
    public func start(now: Date, calendar: Calendar = .current) -> Date? {
        let calendar = gregorian(like: calendar)
        return switch self {
        case .month: calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths: calendar.date(byAdding: .month, value: -3, to: now)
        case .sixMonths: calendar.date(byAdding: .month, value: -6, to: now)
        case .year: calendar.date(byAdding: .year, value: -1, to: now)
        case .all: nil
        }
    }

    /// The points from `start(now:)` on (all of them for `all`), order kept.
    public func filter(_ points: [ChartPoint], now: Date, calendar: Calendar = .current) -> [ChartPoint] {
        guard let start = start(now: now, calendar: calendar) else { return points }
        return points.filter { $0.time >= start }
    }
}
