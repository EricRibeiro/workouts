import Foundation
import Testing

@testable import WorkoutsKit

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

private func candidate(
    _ id: String,
    from startMinute: Double,
    to endMinute: Double,
    kind: HealthActivityKind = .functionalStrength
) -> HealthWorkoutCandidate {
    HealthWorkoutCandidate(id: id, kind: kind, start: at(startMinute), end: at(endMinute), sourceName: "Watch")
}

private func summary(
    _ id: String,
    from startMinute: Double = 0,
    to endMinute: Double = 60,
    series: [HeartRatePoint] = []
)
    -> HealthWorkoutSummary
{
    HealthWorkoutSummary(
        healthWorkoutID: id,
        start: at(startMinute),
        end: at(endMinute),
        activeEnergyKcal: 310,
        totalEnergyKcal: 420,
        avgHeartRate: 118,
        maxHeartRate: 162,
        heartRateSeries: series
    )
}

// Our workout in these tests runs minute 0 to minute 60.

struct HealthMatcherTests {
    let matcher = HealthMatcher()

    private func match(_ candidates: [HealthWorkoutCandidate], claimed: Set<String> = []) -> String? {
        matcher.match(start: at(0), end: at(60), candidates: candidates, claimed: claimed)?.id
    }

    @Test func exactOverlapMatches() {
        #expect(match([candidate("a", from: 0, to: 60)]) == "a")
    }

    @Test func watchStartedThreeMinutesEarlyAndStoppedEightLate() {
        #expect(match([candidate("a", from: -3, to: 68)]) == "a")
    }

    @Test func largerOverlapWins() {
        let near = candidate("near", from: -2, to: 58)
        let far = candidate("far", from: 40, to: 100)
        #expect(match([far, near]) == "near")
        #expect(match([near, far]) == "near")
    }

    @Test func tieGoesToClosestStart() {
        let early = candidate("early", from: -9, to: 51)
        let late = candidate("late", from: -1, to: 59)
        // Both are fully inside the widened window, so overlaps are equal (60 min): closest start wins.
        #expect(match([early, late]) == "late")
        #expect(match([late, early]) == "late")
    }

    @Test func nonStrengthKindsAreIgnored() {
        let run = candidate("run", from: 0, to: 60, kind: .other("running"))
        #expect(match([run]) == nil)
        let traditional = candidate("trad", from: 0, to: 60, kind: .traditionalStrength)
        #expect(match([run, traditional]) == "trad")
    }

    @Test func noOverlapIsNil() {
        #expect(match([candidate("a", from: 120, to: 180)]) == nil)
        #expect(match([]) == nil)
    }

    @Test func outsideTheSlackIsNil() {
        // Ended 20 min before we started, and started 30 min after we finished.
        #expect(match([candidate("before", from: -80, to: -20)]) == nil)
        #expect(match([candidate("after", from: 90, to: 150)]) == nil)
    }

    @Test func insideTheSlackButNotTouchingOurIntervalIsNil() {
        #expect(match([candidate("a", from: -9, to: -1)]) == nil)
    }

    @Test func tinyOverlapIsRejected() {
        // Only the last 5 minutes of ours: 20 min against the widened window, 33% of the shorter (60 min).
        #expect(match([candidate("a", from: 55, to: 115)]) == nil)
    }

    @Test func overlapJustAboveTheThresholdIsAccepted() {
        // 30 of 60 minutes plus the 15 slack = 45 min, 75%.
        #expect(match([candidate("a", from: 30, to: 90)]) == "a")
    }

    @Test func claimedCandidateIsSkipped() {
        let a = candidate("a", from: 0, to: 60)
        let b = candidate("b", from: 10, to: 70)
        #expect(match([a, b], claimed: ["a"]) == "b")
        #expect(match([a], claimed: ["a"]) == nil)
    }

    @Test func zeroLengthWorkoutNeverMatches() {
        #expect(matcher.match(start: at(0), end: at(0), candidates: [candidate("a", from: -5, to: 5)]) == nil)
    }

    @Test func windowAppliesTheSlack() {
        let window = matcher.window(start: at(0), end: at(60))
        #expect(window.start == at(-10))
        #expect(window.end == at(75))
    }
}

struct HealthHeartRateSeriesTests {
    private func series(count: Int, peakAt peakIndex: Int) -> [HeartRatePoint] {
        (0..<count).map { i in
            HeartRatePoint(offset: Double(i) * 5, bpm: i == peakIndex ? 181 : 100 + Double(i % 20))
        }
    }

    @Test func keepsCountUnderTheMaxAndPreservesTheMaxBpm() {
        let points = series(count: 1_000, peakAt: 437)
        let down = HeartRateSeries.downsample(points, maxPoints: 50)
        #expect(down.count <= 50)
        #expect(down.count > 40)
        #expect(down.map(\.bpm).max() == 181)
        #expect(down == down.sorted { $0.offset < $1.offset })
    }

    @Test func shortInputIsReturnedSorted() {
        let points = [HeartRatePoint(offset: 10, bpm: 120), HeartRatePoint(offset: 0, bpm: 100)]
        let down = HeartRateSeries.downsample(points, maxPoints: 5)
        #expect(down.map(\.offset) == [0, 10])
    }

    @Test func bucketsAverageTheNonPeakSamples() {
        let points = [
            HeartRatePoint(offset: 0, bpm: 100), HeartRatePoint(offset: 1, bpm: 110),
            HeartRatePoint(offset: 10, bpm: 130), HeartRatePoint(offset: 11, bpm: 150),
        ]
        let down = HeartRateSeries.downsample(points, maxPoints: 2)
        #expect(down.count == 2)
        #expect(down[0] == HeartRatePoint(offset: 0.5, bpm: 105))
        #expect(down[1] == HeartRatePoint(offset: 11, bpm: 150))  // the peak sample itself
    }

    @Test func degenerateInputs() {
        #expect(HeartRateSeries.downsample([], maxPoints: 10).isEmpty)
        #expect(HeartRateSeries.downsample(series(count: 5, peakAt: 2), maxPoints: 0).isEmpty)
        let sameInstant = (0..<5).map { HeartRatePoint(offset: 3, bpm: 100 + Double($0)) }
        #expect(HeartRateSeries.downsample(sameInstant, maxPoints: 2) == [HeartRatePoint(offset: 3, bpm: 104)])
    }
}

struct HealthEnrichmentTests {
    @Test func returnsTheMatchedSummary() async throws {
        let source = FakeHealthSource(
            candidates: [
                candidate("run", from: 0, to: 60, kind: .other("running")),
                candidate("a", from: -3, to: 68),
            ],
            summaries: [summary("a", from: -3, to: 68), summary("run")]
        )
        let result = try await HealthEnrichment(source: source)
            .enrich(workoutStart: at(0), workoutEnd: at(60), claimed: [])
        #expect(result?.healthWorkoutID == "a")
        #expect(result?.activeEnergyKcal == 310)
        #expect(result?.duration == 4260.0)
    }

    @Test func downsamplesTheSeries() async throws {
        let points = (0..<500).map { HeartRatePoint(offset: Double($0) * 8, bpm: 110 + Double($0 % 30)) }
        let source = FakeHealthSource(
            candidates: [candidate("a", from: 0, to: 60)],
            summaries: [summary("a", series: points)]
        )
        let result = try await HealthEnrichment(source: source, maxSeriesPoints: 40)
            .enrich(workoutStart: at(0), workoutEnd: at(60))
        #expect((result?.heartRateSeries.count ?? 0) <= 40)
        #expect(result?.heartRateSeries.isEmpty == false)
    }

    @Test func noMatchIsNil() async throws {
        let source = FakeHealthSource(candidates: [candidate("a", from: 300, to: 360)], summaries: [summary("a")])
        let result = try await HealthEnrichment(source: source).enrich(workoutStart: at(0), workoutEnd: at(60))
        #expect(result == nil)
    }

    @Test func claimedWorkoutIsNotReturned() async throws {
        let source = FakeHealthSource(candidates: [candidate("a", from: 0, to: 60)], summaries: [summary("a")])
        let result = try await HealthEnrichment(source: source)
            .enrich(workoutStart: at(0), workoutEnd: at(60), claimed: ["a"])
        #expect(result == nil)
    }

    @Test func sourceErrorsPropagate() async {
        let source = FakeHealthSource.failing(.notAuthorized)
        await #expect(throws: HealthSourceError.notAuthorized) {
            _ = try await HealthEnrichment(source: source).enrich(workoutStart: at(0), workoutEnd: at(60))
        }
    }

    @Test func missingSummaryThrowsNotFound() async {
        let source = FakeHealthSource(candidates: [candidate("a", from: 0, to: 60)])
        await #expect(throws: HealthSourceError.notFound) {
            _ = try await HealthEnrichment(source: source).enrich(workoutStart: at(0), workoutEnd: at(60))
        }
    }
}

struct HealthCodableTests {
    @Test func summaryRoundTrips() throws {
        let original = summary(
            "abc",
            series: [HeartRatePoint(offset: 0, bpm: 90), HeartRatePoint(offset: 30, bpm: 140.5)]
        )
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(HealthWorkoutSummary.self, from: data) == original)
    }

    @Test func summaryWithMissingValuesRoundTrips() throws {
        let original = HealthWorkoutSummary(healthWorkoutID: "x", start: at(0), end: at(30))
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(HealthWorkoutSummary.self, from: data) == original)
    }

    @Test func candidateKindsRoundTrip() throws {
        let kinds: [HealthActivityKind] = [.functionalStrength, .traditionalStrength, .other("yoga")]
        let data = try JSONEncoder().encode(kinds)
        #expect(try JSONDecoder().decode([HealthActivityKind].self, from: data) == kinds)
        #expect(kinds.map(\.isStrength) == [true, true, false])
    }

    @Test func fakeSourceFiltersByInterval() async throws {
        let source = FakeHealthSource(candidates: [
            candidate("in", from: 0, to: 60), candidate("out", from: 500, to: 560),
        ])
        let found = try await source.workouts(in: DateInterval(start: at(-10), end: at(75)))
        #expect(found.map(\.id) == ["in"])
    }
}
